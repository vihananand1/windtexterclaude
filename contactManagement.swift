// MARK: - Contact Management Views - FIXED VERSION

import SwiftUI
import Contacts

// MARK: - Main Contacts View
struct ContactsView: View {
    @State private var contacts: [Contact] = []
    @State private var showingAddContact = false
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts.sorted { $0.name < $1.name }
        } else {
            return contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                contact.email?.localizedCaseInsensitiveContains(searchText) == true ||
                contact.phoneNumber?.localizedCaseInsensitiveContains(searchText) == true
            }.sorted { $0.name < $1.name }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search bar
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                
                if filteredContacts.isEmpty {
                    EmptyContactsView(showingAddContact: $showingAddContact)
                } else {
                    List {
                        ForEach(filteredContacts) { contact in
                            NavigationLink(destination: ContactDetailView(contact: contact, contacts: $contacts)) {
                                ContactRowView(contact: contact)
                            }
                        }
                        .onDelete(perform: deleteContacts)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddContact = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
                
                if !contacts.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                ModifiedAddContactView { newContact in
                    contacts.append(newContact)
                    saveContacts()
                }
            }
            .onAppear {
                loadContacts()
            }
        }
    }
    
    private func deleteContacts(offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
        saveContacts()
    }
    
    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }
    
    private func loadContacts() {
        if let data = UserDefaults.standard.data(forKey: "savedContacts"),
           let decoded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = decoded
        }
    }
}

// MARK: - Contact Row View - FIXED
struct ContactRowView: View {
    let contact: Contact
    @Environment(\.colorScheme) var colorScheme
    
    var availablePaths: [String] {
        getAvailablePathsForContact(contact)
    }
    
    var savedPaths: [String] {
        getSavedPathsForContact(contact)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Contact Avatar
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(contact.name.prefix(1).uppercased()))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Name
                Text(contact.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Contact methods
                VStack(alignment: .leading, spacing: 2) {
                    if let email = contact.email {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if let phone = contact.phoneNumber {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(phone)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Available paths indicator
            VStack(alignment: .trailing, spacing: 4) {
                if !savedPaths.isEmpty {
                    Text("Active")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                } else {
                    Text("Paths")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                    let displayPaths = savedPaths.isEmpty ? availablePaths : savedPaths
                    ForEach(displayPaths.prefix(2), id: \.self) { path in
                        PathBadge(path: path, size: .small)
                    }
                    
                    if displayPaths.count > 2 {
                        Text("+\(displayPaths.count - 2)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func getAvailablePathsForContact(_ contact: Contact) -> [String] {
        var paths: [String] = []
        
        if contact.phoneNumber != nil {
            paths.append("SMS")
        }
        if contact.email != nil {
            paths.append("Email")
        }
        return paths
    }
    
    private func getSavedPathsForContact(_ contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
}

// MARK: - Contact Detail View - FIXED
struct ContactDetailView: View {
    let contact: Contact
    @Binding var contacts: [Contact]
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var availablePaths: [String] {
        getAvailablePathsForContact(contact)
    }
    
    var savedPaths: [String] {
        getSavedPathsForContact(contact)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(String(contact.name.prefix(1).uppercased()))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    
                    Text(contact.name)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top)
                
                // Contact Information
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Contact Information")
                    
                    VStack(spacing: 12) {
                        if let email = contact.email {
                            ContactInfoRow(
                                icon: "envelope.fill",
                                title: "Email",
                                value: email,
                                color: .blue
                            )
                        }
                        
                        if let phone = contact.phoneNumber {
                            ContactInfoRow(
                                icon: "phone.fill",
                                title: "Phone",
                                value: phone,
                                color: .green
                            )
                        }
                    }
                }
                
                // Delivery Paths Configuration
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Delivery Paths Configuration")
                    
                    if !savedPaths.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Currently Active Paths")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(savedPaths, id: \.self) { path in
                                    ActivePathCard(path: path, contact: contact)
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: savedPaths.isEmpty ? "info.circle" : "plus.circle")
                                .foregroundColor(.blue)
                            Text(savedPaths.isEmpty ? "Available Paths" : "Other Available Paths")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            let pathsToShow = savedPaths.isEmpty ? availablePaths : availablePaths.filter { !savedPaths.contains($0) }
                            ForEach(pathsToShow, id: \.self) { path in
                                PathCard(path: path, contact: contact)
                            }
                        }
                    }
                }
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        showingEditSheet = true
                    }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit Contact")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Contact")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(12)
                    }
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditContactView(contact: contact) { updatedContact in
                if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
                    contacts[index] = updatedContact
                    saveContacts()
                }
            }
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteContact()
            }
        } message: {
            Text("Are you sure you want to delete \(contact.name)? This action cannot be undone.")
        }
    }
    
    private func getAvailablePathsForContact(_ contact: Contact) -> [String] {
        var paths: [String] = []
        
        if contact.phoneNumber != nil {
            paths.append("SMS")
        }
        if contact.email != nil {
            paths.append("Email")
        }
        
        paths.append("WindTexter")
        return paths
    }
    
    private func getSavedPathsForContact(_ contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    
    private func deleteContact() {
        contacts.removeAll { $0.id == contact.id }
        saveContacts()
        dismiss()
    }
    
    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }
}

// MARK: - Edit Contact View (wrapper around your existing AddContactView)
struct EditContactView: View {
    let contact: Contact
    let onSave: (Contact) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        // Use your existing AddContactView but pre-populate with contact data
        ModifiedAddContactView(
            existingContact: contact,
            onSave: { updatedContact in
                onSave(updatedContact)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}

// MARK: - Modified AddContactView for editing - FIXED
struct ModifiedAddContactView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let existingContact: Contact?
    let onSave: (Contact) -> Void
    let onCancel: (() -> Void)?
    
    @State private var availablePaths: [String] = []
    @State private var isChecking: Bool = false
    @State private var name: String
    @State private var phoneNumber: String
    @State private var email: String
    @State private var selectedRegionCode: String
    
    init(existingContact: Contact? = nil, onSave: @escaping (Contact) -> Void, onCancel: (() -> Void)? = nil) {
        self.existingContact = existingContact
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Initialize state with existing contact data if editing
        _name = State(initialValue: existingContact?.name ?? "")
        _email = State(initialValue: existingContact?.email ?? "")
        
        // Extract phone number without country code if editing
        let phoneWithoutCode = existingContact?.phoneNumber?.replacingOccurrences(of: "^\\+\\d+", with: "", options: .regularExpression) ?? ""
        _phoneNumber = State(initialValue: phoneWithoutCode)
        
        // Try to detect region from phone number, default to first country
        let detectedRegion = existingContact?.phoneNumber != nil ?
            ModifiedAddContactView.detectRegionFromPhone(existingContact!.phoneNumber!) :
            countries.first!.regionCode
        _selectedRegionCode = State(initialValue: detectedRegion)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Contact Info")) {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        
                    Picker("Country Code", selection: $selectedRegionCode) {
                        ForEach(countries) { country in
                            let label = "\(country.name) (\(country.code))"
                            Text(label).tag(country.regionCode)
                        }
                    }
                    
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                }

                Section(header: Text("Available Delivery Paths")) {
                    if isChecking {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking available paths...")
                                .foregroundColor(.gray)
                        }
                    } else if availablePaths.isEmpty {
                        Text("No paths available")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(availablePaths, id: \.self) { path in
                            HStack {
                                PathBadge(path: path, size: .small)
                                
                                Text(getPathDescription(path))
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                // Show current paths if editing
                if let contact = existingContact {
                    Section(header: Text("Currently Saved Paths")) {
                        let currentPaths = getCurrentlySavedPaths(for: contact)
                        if currentPaths.isEmpty {
                            Text("No paths previously configured")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(currentPaths, id: \.self) { path in
                                HStack {
                                    PathBadge(path: path, size: .small)
                                    Text("Previously configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingContact == nil ? "Add Contact" : "Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContact()
                    }
                    .disabled(name.isEmpty || (phoneNumber.isEmpty && email.isEmpty))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel = onCancel {
                            onCancel()
                        } else {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .onChange(of: phoneNumber) { _ in checkPaths() }
            .onChange(of: email) { _ in checkPaths() }
            .onChange(of: selectedRegionCode) { _ in checkPaths() }
            .onAppear {
                if existingContact != nil {
                    checkPaths() // Check paths when editing existing contact
                }
            }
        }
    }
    
    private func saveContact() {
        let country = countries.first(where: { $0.regionCode == selectedRegionCode }) ?? countries[0]
        let fullNumber = phoneNumber.isEmpty ? nil : (country.code + phoneNumber)
        
        let contact = Contact(
            name: name,
            phoneNumber: fullNumber,
            email: email.isEmpty ? nil : email
        )

        // Save available paths to UserDefaults
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        UserDefaults.standard.set(availablePaths, forKey: key)

        onSave(contact)
        
        if onCancel == nil {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func checkPaths() {
        guard !phoneNumber.isEmpty || !email.isEmpty else {
            availablePaths = []
            return
        }

        let country = countries.first(where: { $0.regionCode == selectedRegionCode }) ?? countries[0]
        let fullNumber = phoneNumber.isEmpty ? nil : (country.code + phoneNumber)
        let contact = Contact(
            name: name,
            phoneNumber: fullNumber,
            email: email.isEmpty ? nil : email
        )

        isChecking = true
        
        fetchAvailablePaths(for: contact, region: selectedRegionCode) { regionPaths in
            DispatchQueue.main.async {
                let userEnabledPaths = self.getUserEnabledPaths()
                let finalPaths = regionPaths.filter { userEnabledPaths.contains($0) }
                
                self.availablePaths = finalPaths
                self.isChecking = false
            }
        }
    }
    
    private func getUserEnabledPaths() -> Set<String> {
        guard let selectedPathsData = UserDefaults.standard.data(forKey: "selectedPaths"),
              let enabledPaths = try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData) else {
            return Set(getAvailablePathsForCurrentRegion().filter { $0 != "WindTexter" })
        }
        return enabledPaths
    }
    
    private func getPathDescription(_ path: String) -> String {
        switch path.lowercased() {
        case "sms": return "Text messaging"
        case "email", "send_email": return "Email messaging"
        case "windtexter": return "Direct secure channel"
        default: return path
        }
    }
    
    private func getCurrentlySavedPaths(for contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    
    // Helper function to detect region from phone number
    static func detectRegionFromPhone(_ phoneNumber: String) -> String {
        for country in countries {
            if phoneNumber.hasPrefix(country.code) {
                return country.regionCode
            }
        }
        return countries.first!.regionCode
    }
}

// MARK: - Supporting Views

struct ActivePathCard: View {
    let path: String
    let contact: Contact
    
    var pathDescription: String {
        switch path.lowercased() {
        case "sms": return "Text messaging active"
        case "email", "send_email": return "Email messaging active"
        case "windtexter": return "Secure channel active"
        default: return "Active"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search contacts...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct EmptyContactsView: View {
    @Binding var showingAddContact: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Contacts Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your first contact to start secure messaging")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showingAddContact = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Contact")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
    }
}

struct ContactInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
            
            Button(action: {
                // Copy to clipboard
                UIPasteboard.general.string = value
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

enum BadgeSize {
    case small, medium, large
    
    var font: Font {
        switch self {
        case .small: return .caption2
        case .medium: return .caption
        case .large: return .body
        }
    }
    
    var padding: (horizontal: CGFloat, vertical: CGFloat) {
        switch self {
        case .small: return (4, 2)
        case .medium: return (8, 4)
        case .large: return (12, 6)
        }
    }
}

struct PathBadge: View {
    let path: String
    let size: BadgeSize
    
    var pathColor: Color {
        switch path.lowercased() {
        case "sms": return .green
        case "email": return .blue
        case "windtexter": return .purple
        default: return .gray
        }
    }
    
    var pathIcon: String {
        switch path.lowercased() {
        case "sms": return "message.fill"
        case "email": return "envelope.fill"
        case "windtexter": return "wind"
        default: return "questionmark"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pathIcon)
                .font(size.font)
            Text(path)
                .font(size.font)
                .fontWeight(.medium)
        }
        .padding(.horizontal, size.padding.horizontal)
        .padding(.vertical, size.padding.vertical)
        .background(pathColor.opacity(0.2))
        .foregroundColor(pathColor)
        .cornerRadius(8)
    }
}

struct PathCard: View {
    let path: String
    let contact: Contact
    
    var isAvailable: Bool {
        switch path.lowercased() {
        case "sms": return contact.phoneNumber != nil
        case "email": return contact.email != nil
        case "windtexter": return true
        default: return false
        }
    }
    
    var pathDescription: String {
        switch path.lowercased() {
        case "sms": return "Send via text message"
        case "email": return "Send via email"
        case "windtexter": return "Direct secure channel"
        default: return ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isAvailable ? .green : .red)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
