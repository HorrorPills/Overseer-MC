//
//  EntityManagementView.swift
//  Overseer
//
//  The strictly-vanilla equivalent of a ClearLagg/EssentialsX clearlag
//  plugin: periodically (or on demand) sweeps out disposable entities —
//  dropped items, XP orbs, and opt-in stray projectiles/primed TNT/
//  hostile mobs — via `/kill @e[type=...]` over RCON. See
//  EntityCleanupCatalog for exactly which entity types each category
//  covers and why (bosses, mounts, and the Warden are deliberately never
//  included, even under "Hostile Mobs").
//
//  Config lives in AppSettings (persisted) and is mirrored onto
//  RCONAutomationCoordinator's live properties via .onChange — the same
//  split SettingsView already uses for rconAutomationEnabled/
//  rconTickPollInterval, rather than the coordinator reading AppSettings
//  directly.
//

import SwiftUI

struct EntityManagementView: View {
    @Bindable var settings: AppSettings
    var rconCoordinator: RCONAutomationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                scheduleSection
                Divider()
                categoriesSection
                Divider()
                warningSection
                Divider()
                manualSection
            }
            .padding(20)
        }
        .navigationTitle("Entity Management")
        .onChange(of: settings.entityCleanupEnabled) { _, newValue in rconCoordinator.entityCleanupEnabled = newValue }
        .onChange(of: settings.entityCleanupIntervalMinutes) { _, newValue in rconCoordinator.entityCleanupIntervalMinutes = newValue }
        .onChange(of: settings.entityCleanupCategories) { _, newValue in rconCoordinator.entityCleanupCategories = newValue }
        .onChange(of: settings.entityCleanupWarnBeforeClear) { _, newValue in rconCoordinator.entityCleanupWarnBeforeClear = newValue }
        .onChange(of: settings.entityCleanupWarnLeadSeconds) { _, newValue in rconCoordinator.entityCleanupWarnLeadSeconds = newValue }
        .onChange(of: settings.entityCleanupWarnMessage) { _, newValue in rconCoordinator.entityCleanupWarnMessage = newValue }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatic Sweep").font(.headline)
            Toggle("Automatically clear every \(Int(settings.entityCleanupIntervalMinutes)) minutes", isOn: $settings.entityCleanupEnabled)
            Stepper(value: $settings.entityCleanupIntervalMinutes, in: 1...120, step: 1) {
                Text("Interval: \(Int(settings.entityCleanupIntervalMinutes)) minute\(Int(settings.entityCleanupIntervalMinutes) == 1 ? "" : "s")")
            }
            .disabled(!settings.entityCleanupEnabled)
            Text("This only affects the entity types checked below — nothing runs for a category you leave off, scheduled or manual.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("If Hostile Mobs is on: killed mobs drop their normal loot (rotten flesh, bones, etc. — confirmed via the kill command's death event), so that pass always runs before Dropped Items in the same sweep, catching the loot immediately rather than leaving it for the next run. Primed TNT despawns with no explosion and no drops either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Gets Cleared").font(.headline)
            VStack(spacing: 0) {
                categoryRow(.droppedItems, isOn: $settings.entityCleanupClearItems)
                Divider()
                categoryRow(.experienceOrbs, isOn: $settings.entityCleanupClearXPOrbs)
                Divider()
                categoryRow(.projectiles, isOn: $settings.entityCleanupClearProjectiles)
                Divider()
                categoryRow(.primedTNT, isOn: $settings.entityCleanupClearTNT)
                Divider()
                categoryRow(.hostileMobs, isOn: $settings.entityCleanupClearHostileMobs)
                Divider()
                categoryRow(.enderPearls, isOn: $settings.entityCleanupClearEnderPearls)
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("Never touched, no matter what's checked above: item frames, armor stands, paintings, boats, minecarts, tamed/mountable animals, villagers, and boss mobs (Wither, Ender Dragon). Only genuinely disposable entities are ever offered here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryRow(_ category: LagClearCategory, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                HStack(spacing: 6) {
                    Image(systemName: category.systemImage).foregroundStyle(.secondary).frame(width: 18)
                    Text(category.label)
                }
            }
            .help(EntityCleanupCatalog.selectors(for: category).joined(separator: ", "))
            if let riskNote = category.riskNote, isOn.wrappedValue {
                Label(riskNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }

    // MARK: - Warning broadcast

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pre-Clear Warning").font(.headline)
            Toggle("Warn players before clearing", isOn: $settings.entityCleanupWarnBeforeClear)
            if settings.entityCleanupWarnBeforeClear {
                Stepper(value: $settings.entityCleanupWarnLeadSeconds, in: 5...120, step: 5) {
                    Text("Warn \(Int(settings.entityCleanupWarnLeadSeconds))s before clearing")
                }
                TextField("Warning message", text: $settings.entityCleanupWarnMessage)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text("Sweeps run silently — no chat message before or after.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Manual trigger + last result

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manual Sweep").font(.headline)
            HStack(spacing: 12) {
                Button {
                    Task { await rconCoordinator.runEntityCleanup(categories: settings.entityCleanupCategories) }
                } label: {
                    if rconCoordinator.isRunningEntityCleanup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Clear Now", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(rconCoordinator.isRunningEntityCleanup || settings.entityCleanupCategories.isEmpty)

                if settings.entityCleanupCategories.isEmpty {
                    Text("Check at least one category above.").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let result = rconCoordinator.lastEntityCleanupResult {
                lastResultCard(result)
            }
        }
    }

    private func lastResultCard(_ result: RCONAutomationCoordinator.EntityCleanupResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last sweep").font(.subheadline.weight(.semibold))
                Spacer()
                Text(result.timestamp, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if result.perCategory.isEmpty {
                Text("Nothing to clear — no categories were enabled.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(result.perCategory.sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { category, count in
                    HStack {
                        Text(category.label).font(.caption)
                        Spacer()
                        Text("\(count)").font(.caption.monospacedDigit().weight(.medium))
                    }
                }
                Divider()
                HStack {
                    Text("Total").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(result.totalKilled)").font(.caption.monospacedDigit().weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
