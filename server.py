"""
server.py

WindTexter backend API and message relay server.
Handles sending and receiving messages via email and SMS, message encryption/compression,
storage, and integration with NLP models for auto-reply. Provides REST API endpoints
for client apps to interact with the system.
"""

from flask import Flask, request, jsonify
from typing import List
from transformers import GPT2LMHeadModel, GPT2Tokenizer
import torch
import json
from Config.config_loader import load_config
from datetime import datetime, timezone
from twilio.rest import Client
import smtplib
from email.message import EmailMessage
from Compression.compression import Compressor
from Encryption.encryption import Encryptor, bytes2bits, bits2bytes
from bitarray import bitarray
import secrets
from dotenv import load_dotenv
import os, binascii
import codecs
load_dotenv()

# Email credentials for SMTP
SMTP_EMAIL = "windtexter@gmail.com"
SMTP_PASSWORD = "ndiwzmzqxecidfed"

# Flask app setup
app = Flask(__name__)

# Load configuration and defaults
config = load_config()
DEFAULT_COMPRESSION_METHOD = 'utf8'
DEFAULT_ENCRYPTION_MODE = config["encryption"]["cipher_mode"]
DEFAULT_KEY_LENGTH = config["encryption"]["key_length"]

DEFAULT_KEY = b"thisis16byteskey"
DEFAULT_IV = b"initialvector123"


def validate_path(delivery_path):
    """
    Checks if the delivery_path is valid for sending messages (email, sms, windtexter).
    Returns True if valid, else False.
    """
    valid_paths = ["email", "sms", "windtexter"]
    if delivery_path not in valid_paths:
        return False
    return True

@app.route("/send_email", methods=["POST"])
def send_email():
    """
    API endpoint to send an email message using SMTP.
    Expects JSON with 'to', 'message', and optional 'subject' and 'delivery_path'.
    Returns status or error in JSON response.
    """
    data = request.json
    to = data.get("to")
    message = data.get("message")
    subject = data.get("subject", "WindTexter")
    delivery_path = data.get("delivery_path", "")

    # Map legacy/alias delivery paths to canonical names
    alias_map = {
        "send_email": "email",
        "send_sms": "sms"
    }
    delivery_path = alias_map.get(delivery_path, delivery_path)

    if not to or not message:
        return jsonify({"error": "Missing fields"}), 400

    if not validate_path(delivery_path):
        return jsonify({"error": f"Invalid path: {delivery_path}"}), 400

    try:
        msg = EmailMessage()
        msg.set_content(message)
        msg["Subject"] = subject
        msg["From"] = SMTP_EMAIL
        msg["To"] = to

        # Use SMTP_SSL for secure email sending
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(SMTP_EMAIL, SMTP_PASSWORD)
            smtp.send_message(msg)

        return jsonify({"status": "sent"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

TWILIO_SID = "AC9aec599bd9f3cbe256412b3edf206d68"
TWILIO_AUTH = "64f785f72b086bde5a5980b55801375b"
TWILIO_FROM = "+16672184308"

@app.route("/send_sms", methods=["POST"])
def send_sms():
    data = request.json
    to = data.get("to")
    message = data.get("message")
    sender_id = data.get("sender_id")  # ✅ Optional, pass from client
    real_text = data.get("real_text")
    bitstream = data.get("bitstream", [])
    bit_count = data.get("bit_count", 0)
    message_id = data.get("id") or str(uuid.uuid4())

    if not to or not message:
        return jsonify({"error": "Missing fields"}), 400

    try:
        client = Client(TWILIO_SID, TWILIO_AUTH)
        msg = client.messages.create(
            body=message,
            from_=TWILIO_FROM,
            to=to
        )

        # ✅ After sending, store it
        stored_data = {
            "id": message_id,
            "real_text": real_text,
            "cover_text": message,
            "bitstream": bitstream,
            "bit_count": bit_count,
            "delivery_path": "sms",
            "sender_id": sender_id,
            "is_sent_by_current_user": True
        }

        # You can call store_message logic directly here or forward via requests.post
        from flask import json
        with app.test_request_context():
            with app.test_client() as client:
                client.post('/store_message', json=stored_data)

        return jsonify({"status": "sent", "sid": msg.sid})

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# Load tokenizer and model
model_name = "distilgpt2"
tokenizer = GPT2Tokenizer.from_pretrained(model_name)
model = GPT2LMHeadModel.from_pretrained(model_name)
model.eval()

CHUNK_SIZE = 4
TOP_K = 2 ** CHUNK_SIZE

STORAGE_PATH = "api_storage"
os.makedirs(STORAGE_PATH, exist_ok=True)

def text_to_bits(text: str, method: str = DEFAULT_COMPRESSION_METHOD) -> list[int]:
    compressor = Compressor(method=method)
    compressed_bits = compressor.compress(text)

    print(f"[DEBUG] Compressed bits ({len(compressed_bits)} bits): {compressed_bits[:64]}...")

    # ✅ Determine IV only if OFB mode
    iv_arg = DEFAULT_IV if DEFAULT_ENCRYPTION_MODE == 'OFB' else None

    encryptor = Encryptor(
        mode=DEFAULT_ENCRYPTION_MODE,
        key=DEFAULT_KEY,
        key_length=DEFAULT_KEY_LENGTH,
        iv=iv_arg
    )

    encrypted_bits = encryptor.encrypt(compressed_bits)

    print(f"[DEBUG] Encrypted bits ({len(encrypted_bits)} bits): {encrypted_bits[:64]}...")

    return encrypted_bits


def bits_to_text(bits: list[int], method: str = DEFAULT_COMPRESSION_METHOD) -> str:
    print("[DEBUG] bits_to_text(): Starting")
    
    if method == "default":
        method = 'utf8'

    encryptor = Encryptor(
        mode=DEFAULT_ENCRYPTION_MODE,
        key=DEFAULT_KEY,
        key_length=DEFAULT_KEY_LENGTH,
        iv=None
    )

    try:
        print("[DEBUG] Decrypting...")
        decrypted_bits = encryptor.decrypt(bits)
        print(f"[DEBUG] Decrypted {len(decrypted_bits)} bits")
    except Exception as e:
        print(f"[ERROR] Decryption failed: {e}")
        raise

    try:
        print(f"[DEBUG] Decompressing using method: {method}")
        compressor = Compressor(method=method)
        text = compressor.decompress(decrypted_bits)
        print("[DEBUG] Decompression successful")
        return text
    except Exception as e:
        print(f"[ERROR] Decompression failed: {e}")
        raise

def encode_message_to_cover_text(bit_sequence):
    import random
    style_prompts = [
        "Say something casual like you're texting a friend. Keep it under 2 sentences.",
        "Write a short, vague message someone might send in chat. Keep it brief.",
        "Text something natural and ambiguous in under 20 words.",
        "Casual chat message. Two sentences max. Sounds normal.",
        "Make it sound like a quick message to a friend. Nothing specific."
    ]
    seed_prompt = random.choice(style_prompts)
    input_ids = tokenizer.encode(seed_prompt, return_tensors="pt")
    generated_tokens = []
    used_chunks = 0

    while len(bit_sequence) % CHUNK_SIZE != 0:
        bit_sequence.append(0)
    bit_chunks = [bit_sequence[i:i + CHUNK_SIZE] for i in range(0, len(bit_sequence), CHUNK_SIZE)]

    for chunk in bit_chunks:
        target_index = int(''.join(map(str, chunk)), 2)
        with torch.no_grad():
            outputs = model(input_ids=input_ids)
        logits = outputs.logits[:, -1, :].squeeze()
        sorted_indices = torch.topk(logits, TOP_K).indices.tolist()
        token_id = sorted_indices[target_index % len(sorted_indices)]
        token_str = tokenizer.decode([token_id], skip_special_tokens=True, clean_up_tokenization_spaces=True)
        token_str = ''.join(char for char in token_str if char.isprintable() and ord(char) < 128)
        generated_tokens.append(token_str)
        used_chunks += 1
        next_token_tensor = torch.tensor([[token_id]], dtype=torch.long)
        input_ids = torch.cat([input_ids, next_token_tensor], dim=1)
        joined = "".join(generated_tokens).strip()
        if joined.count(".") + joined.count("!") + joined.count("?") >= 2 or len(joined.split()) > 20:
            break
    return "".join(generated_tokens).strip(), used_chunks * CHUNK_SIZE

@app.route('/decode_cover_chunks', methods=['POST'])
def decode_cover_chunks():
    data = request.json
    bit_sequence = data.get("bit_sequence", [])
    method = data.get("compression_method", DEFAULT_COMPRESSION_METHOD)

    # 🔁 Convert all bits to integers in case they're strings
    bit_sequence = [int(b) for b in bit_sequence]

    if not bit_sequence:
        print("[ERROR] Received empty bit_sequence")
        return jsonify({"error": "Empty bit_sequence"}), 400

    if not isinstance(bit_sequence, list) or not all(bit in [0, 1] for bit in bit_sequence):
        return jsonify({"error": "Invalid bit_sequence"}), 400

    try:
        print(f"[DEBUG] Received bit_sequence (len={len(bit_sequence)}): {bit_sequence[:32]}")
        print(f"[DEBUG] Compression method: {method}")

        print("[DEBUG] Calling bits_to_text...")
        decoded_text = bits_to_text(bit_sequence, method)
        print("[DEBUG] Decoding successful.")

        return jsonify({"decoded_text": decoded_text})
    except Exception as e:
        print(f"[ERROR] decode_cover_chunks failed: {str(e)}")
        return jsonify({"error": str(e)}), 500



@app.route("/split_cover_chunks", methods=["POST"])
def split_cover_chunks():
    data = request.json
    message = data.get("message", "")
    path = data.get("path", "WindTexter")

    print(f"[DEBUG] Message received: {message}")
    print(f"[DEBUG] Path received: {path}")

    try:
        bitstream = text_to_bits(message)
        return jsonify({
            "bitstream": [str(b) for b in bitstream],
            "bit_count": len(bitstream)
        })
    except Exception as e:
        print(f"[ERROR] Exception in split_cover_chunks: {e}")
        return "Internal Server Error", 500


@app.route('/fetch_messages', methods=['POST'])
def fetch_messages():
    try:
        data = request.json
        path = data.get("delivery_path", "generic")
        device_id = data.get("device_id")
        
        path_file = os.path.join(STORAGE_PATH, f"{path}_db.json")

        if not os.path.exists(path_file):
            return jsonify({"messages": []})

        with open(path_file, 'r') as f:
            try:
                all_messages = json.load(f)
            except json.JSONDecodeError:
                all_messages = []

        from datetime import datetime, timezone, timedelta
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=10)
        seen_ids = set(data.get("seen_message_ids", []))
        recent_messages = []

        for message in all_messages:
            try:
                timestamp_str = message.get("timestamp", "")
                if timestamp_str.endswith('Z'):
                    timestamp_str = timestamp_str[:-1] + '+00:00'
                elif not timestamp_str.endswith('+00:00'):
                    timestamp_str += '+00:00'

                msg_time = datetime.fromisoformat(timestamp_str)
                msg_id = message.get("id")

                if msg_time > cutoff and msg_id not in seen_ids:
                    recent_messages.append(message)
            except Exception as e:
                continue

        for message in recent_messages:
            msg_sender = message.get("sender_id")
            message["is_sent_by_current_user"] = (msg_sender == device_id)
            
            # ✅ Include image data in response
            if "real_text" in message:
                message["realText"] = message["real_text"]
            if "cover_text" in message:
                message["coverText"] = message["cover_text"]
            if "image_data" in message and message["image_data"]:
                message["imageData"] = message["image_data"]
                print(f"📸 Including image data for message {msg_id}")

        return jsonify({"messages": recent_messages})
        
    except Exception as e:
        print(f"[ERROR] fetch_messages failed: {e}")
        return jsonify({"error": str(e), "messages": []}), 500


@app.route("/send_email_with_image", methods=["POST"])
def send_email_with_image():
    """
    API endpoint to send an email message with optional image attachment using SMTP.
    Expects JSON with 'to', 'message', optional 'subject', 'image_data', and 'image_filename'.
    Returns status or error in JSON response.
    """
    data = request.json
    to = data.get("to")
    message = data.get("message", "")  # ✅ Default to empty string
    subject = data.get("subject", "WindTexter")
    image_data = data.get("image_data")  # Base64 encoded
    image_filename = data.get("image_filename", "image.jpg")

    print(f"📧 send_email_with_image called:")
    print(f"   to: {to}")
    print(f"   message: '{message}'")
    print(f"   has_image: {image_data is not None}")
    if image_data:
        print(f"   image_data length: {len(image_data)} chars")

    if not to:
        print("❌ Missing 'to' field")
        return jsonify({"error": "Missing 'to' field"}), 400
    
    # ✅ FIX: Allow empty message if we have image
    if not message and not image_data:
        print("❌ Missing both message and image")
        return jsonify({"error": "Must provide either message or image"}), 400

    try:
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText
        from email.mime.base import MIMEBase
        from email import encoders
        import base64

        # Create message container
        msg = MIMEMultipart()
        msg["Subject"] = subject
        msg["From"] = SMTP_EMAIL
        msg["To"] = to

        # ✅ FIX: Add text content even if empty
        if message:
            msg.attach(MIMEText(message, "plain"))
        else:
            msg.attach(MIMEText("📸 Image message", "plain"))  # Fallback text

        # ✅ Add image attachment if provided
        if image_data:
            try:
                print(f"🔧 Decoding base64 image data...")
                # Decode base64 image data
                image_bytes = base64.b64decode(image_data)
                print(f"✅ Decoded {len(image_bytes)} bytes")
                
                # Create attachment
                part = MIMEBase("application", "octet-stream")
                part.set_payload(image_bytes)
                encoders.encode_base64(part)
                part.add_header(
                    "Content-Disposition",
                    f"attachment; filename= {image_filename}",
                )
                msg.attach(part)
                print(f"📎 Added image attachment: {image_filename} ({len(image_bytes)} bytes)")
            except Exception as e:
                print(f"❌ Failed to attach image: {e}")
                # Continue without attachment

        print(f"📤 Sending email...")
        # Send email using SMTP_SSL
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(SMTP_EMAIL, SMTP_PASSWORD)
            smtp.send_message(msg)

        print(f"✅ Email sent successfully!")
        return jsonify({"status": "sent"})
    except Exception as e:
        print(f"❌ Email sending failed: {e}")
        import traceback
        traceback.print_exc()  # ✅ Print full error traceback
        return jsonify({"error": str(e)}), 500

@app.route('/generate_reply', methods=['POST'])
def generate_reply():
    data = request.json
    history = data.get("chat_history", [])
    last_message = data.get("last_message", "").strip()
    if not last_message:
        return jsonify({"error": "No last_message provided"}), 400
    context = "\n".join(history[-5:])
    prompt = f"{context}\nUser: {last_message}\nFriend:"
    input_ids = tokenizer.encode(prompt, return_tensors="pt")
    with torch.no_grad():
        output = model.generate(
            input_ids,
            max_length=input_ids.shape[1] + 30,
            num_return_sequences=1,
            pad_token_id=tokenizer.eos_token_id,
            do_sample=True,
            top_k=50,
            top_p=0.95
        )
    reply = tokenizer.decode(output[0], skip_special_tokens=True)
    reply_text = reply[len(prompt):].strip().split("\n")[0]
    return jsonify({"reply": reply_text})

@app.route('/check_available_paths', methods=['POST'])
def check_available_paths():
    data = request.json
    phone = data.get("phone")
    email = data.get("email")
    region = data.get("region", "US")

    available = []

    region_defaults = {
        "US": ["SMS", "Email", "WindTexter"],
        "EU": ["Email", "WindTexter"],
        "IN": ["SMS", "WhatsApp", "WindTexter"],
    }
    available.extend(region_defaults.get(region, ["Email", "WindTexter"]))

    if not phone:
        available = [x for x in available if x != "SMS"]
    if not email:
        available = [x for x in available if x != "Email"]

    if email and email.endswith("@example.com"):
        available.append("WindTexter")

    return jsonify({"availablePaths": sorted(list(set(available)))})

@app.route('/store_message', methods=['POST'])
def store_message():
    data = request.json

    print("📥 /store_message received:")
    # ✅ FIX: Check both field name formats
    real_text = data.get("real_text") or data.get("realText")
    cover_text = data.get("cover_text") or data.get("coverText")
    print("   realText:", real_text)
    print("   coverText:", cover_text)
    print("   imageData present:", "image_data" in data)
    
    if "image_data" in data and data["image_data"]:
        image_data_len = len(data.get("image_data", ""))
        print(f"   imageData size: {image_data_len} characters")
        
        # ✅ Test base64 decoding
        try:
            import base64
            decoded = base64.b64decode(data["image_data"])
            print(f"   Decoded image size: {len(decoded)} bytes")
        except Exception as e:
            print(f"   ❌ Failed to decode image: {e}")

    alias_map = {
        "send_email": "email",
        "send_sms": "sms"
    }

    raw_path = data.get("delivery_path", "generic").lower()
    path = alias_map.get(raw_path, raw_path)

    if not validate_path(path):
        return jsonify({"error": f"Invalid path: {path}"}), 400

    path_file = os.path.join(STORAGE_PATH, f"{path}_db.json")

    is_sent_by_current_user = data.get("is_sent_by_current_user", False)

    complete_data = {
        "id": data.get("id"),
        "delivery_path": path,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "bitstream": data.get("bitstream", []),
        "is_sent_by_current_user": is_sent_by_current_user,
        # ✅ FIX: Handle both field name formats
        "real_text": real_text or "",
        "cover_text": cover_text or "",
        # ✅ FIX: Check both field name formats for other fields too
        "bit_count": data.get("bit_count") or data.get("bitCount", 0),
        "is_auto_reply": data.get("is_auto_reply") or data.get("isAutoReply", False),
        "image_data": data.get("image_data", None),
        "sender_id": data.get("sender_id", None),
    }
    
    print(f"📦 Final data being stored:")
    print(f"   real_text: '{complete_data['real_text']}'")
    print(f"   cover_text: '{complete_data['cover_text'][:50]}...'")
    print(f"   image_data present: {complete_data['image_data'] is not None}")

    if os.path.exists(path_file):
        with open(path_file, 'r') as f:
            try:
                db = json.load(f)
            except json.JSONDecodeError as e:
                db = []
    else:
        db = []

    db.append(complete_data)

    with open(path_file, 'w') as f:
        json.dump(db, f, indent=2)

    print("✅ Message stored successfully")
    return jsonify({"status": "stored", "message": complete_data})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=4000)
