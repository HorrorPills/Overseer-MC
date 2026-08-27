//
//  GiveItemSheet.swift
//  Overseer
//
//  Searchable picker over MinecraftItemCatalog, presented as a sheet
//  from a player's context menu or detail page. Dispatches exactly one
//  vanilla `/give` via RCONAutomationCoordinator.giveItem(to:item:count:),
//  which also logs the ModerationEvent audit entry.
//

import SwiftUI

struct GiveItemSheet: View {
    var username: String
    var coordinator: RCONAutomationCoordinator
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedCategory: MinecraftItemCategory?
    @State private var selectedItem: MinecraftItem?
    @State private var quantity = 1

    private var filteredItems: [MinecraftItem] {
        let base = MinecraftItemCatalog.search(query)
        guard let selectedCategory else { return base }
        return base.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryBar
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 440, height: 500)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Give Item").font(.headline)
                Text("to \(username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search items…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(14)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(nil, label: "All")
                ForEach(MinecraftItemCategory.allCases) { category in
                    categoryChip(category, label: category.rawValue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(_ category: MinecraftItemCategory?, label: String) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    selectedCategory == category ? Color.accentColor : Color.gray.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(selectedCategory == category ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var itemList: some View {
        List(filteredItems, selection: $selectedItem) { item in
            HStack {
                Image(systemName: item.category.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                    Text(item.id).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .tag(item)
            .contentShape(Rectangle())
            .onTapGesture { selectedItem = item }
        }
        .listStyle(.inset)
        .overlay {
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var footer: some View {
        HStack {
            Stepper(value: $quantity, in: 1...64) {
                Text("Quantity: \(quantity)")
            }
            .frame(width: 160)
            Spacer()
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button("Give") { give() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedItem == nil)
        }
        .padding(14)
    }

    private func give() {
        guard let selectedItem else { return }
        Task { await coordinator.giveItem(to: username, item: selectedItem, count: quantity) }
        isPresented = false
    }
}
