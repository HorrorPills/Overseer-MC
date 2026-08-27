//
//  PlayerFilterPicker.swift
//  Overseer
//
//  Searchable multi-select player filter — replaces the plain `Menu`
//  World Map used to use, which meant scrolling through every player
//  the server has ever seen with no way to jump to a name. A popover
//  with a search field in front of the same checkbox list fixes that
//  without needing anything fancier.
//

import SwiftUI

struct PlayerFilterPicker: View {
    var players: [String]
    @Binding var selected: Set<String>

    @State private var isPresented = false
    @State private var searchText = ""

    private var filteredPlayers: [String] {
        guard !searchText.isEmpty else { return players }
        return players.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(buttonTitle, systemImage: "person.crop.circle")
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented) {
            VStack(spacing: 0) {
                TextField("Search players", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                Divider()
                HStack {
                    Button("All Players") { selected.removeAll() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Spacer()
                    if !selected.isEmpty {
                        Text("\(selected.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                if filteredPlayers.isEmpty {
                    Text("No players match \"\(searchText)\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredPlayers, id: \.self) { username in
                                playerRow(username)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            .frame(width: 220)
        }
    }

    private var buttonTitle: String {
        selected.isEmpty ? "All Players" : "\(selected.count) Player\(selected.count == 1 ? "" : "s")"
    }

    private func playerRow(_ username: String) -> some View {
        let isSelected = selected.contains(username)
        return Button {
            if isSelected { selected.remove(username) } else { selected.insert(username) }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(username).font(.callout)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
