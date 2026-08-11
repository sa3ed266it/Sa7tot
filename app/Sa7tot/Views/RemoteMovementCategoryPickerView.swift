import SwiftUI

@available(iOS 26.0, *)
struct RemoteMovementCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator

    @Binding var selectedCategoryID: UUID?
    let income: Bool

    @State private var activatingPresetKeys: Set<String> = []
    @State private var errorMessage: String?
    @State private var showingNewCategory = false
    @State private var pendingCreatedCategoryID: UUID?

    private var activeCategories: [RemoteCategoryDTO] {
        store.categories.filter { $0.income == income }
    }

    private var suggestedPresets: [CategoryPreset] {
        let activePresetKeys = Set(activeCategories.compactMap(\.presetKey))
        let customNames = Set(
            activeCategories
                .filter { $0.presetKey == nil }
                .map { normalizedDisplayName($0.name) }
        )

        return CategoryPresetCatalog.presets(income: income).filter { preset in
            !activePresetKeys.contains(preset.key)
                && !customNames.contains(normalizedDisplayName(preset.localizedTitle))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(AppLocalization.key("category.active"))) {
                    if activeCategories.isEmpty {
                        Text(income ? AppLocalization.key("category.emptyIncomes") : AppLocalization.key("category.emptyExpenses"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeCategories) { category in
                            activeCategoryRow(category)
                        }
                    }
                }

                if !suggestedPresets.isEmpty {
                    Section(header: Text(AppLocalization.key("category.suggested"))) {
                        ForEach(suggestedPresets) { preset in
                            suggestedPresetRow(preset)
                        }
                    }
                }

                Section {
                    Button {
                        showingNewCategory = true
                    } label: {
                        Label(AppLocalization.key("action.addCategory"), systemImage: "plus.circle.fill")
                    }
                    .accessibilityLabel(AppLocalization.key("action.addCategory"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(AppLocalization.key("category.choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.key("action.cancel")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingNewCategory, onDismiss: finishCreatedCategory) {
            RemoteCategoryEditorView(
                category: nil,
                initialIncome: income,
                onCreated: { createdCategory in
                    guard createdCategory.income == income else {
                        errorMessage = AppLocalization.string("category.saveError")
                        return
                    }
                    pendingCreatedCategoryID = createdCategory.id
                }
            )
            .environmentObject(store)
            .environmentObject(appToastCoordinator)
        }
        .alert(
            AppLocalization.key("common.error"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(AppLocalization.key("action.ok"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? AppLocalization.string("category.activateError"))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func activeCategoryRow(_ category: RemoteCategoryDTO) -> some View {
        Button {
            selectedCategoryID = category.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CategoryIconView(
                    descriptor: CategoryIconPresentation.descriptor(for: category.iconIdentifier),
                    role: .category,
                    tint: Color(hex: category.color),
                    accessibilityLabel: category.name
                )
                .frame(width: 32, height: 32)

                Text(category.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if selectedCategoryID == category.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(selectedCategoryID == category.id ? .isSelected : [])
    }

    private func suggestedPresetRow(_ preset: CategoryPreset) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(
                descriptor: .sfSymbol(preset.symbolName),
                role: .category,
                tint: Color(hex: preset.defaultColor),
                accessibilityLabel: preset.localizedTitle
            )
            .frame(width: 32, height: 32)

            Text(preset.localizedTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                activate(preset)
            } label: {
                if activatingPresetKeys.contains(preset.key) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.borderless)
            .disabled(activatingPresetKeys.contains(preset.key))
            .accessibilityLabel(AppLocalization.format("category.addSuggested", preset.localizedTitle))
        }
        .frame(minHeight: 44)
    }

    private func activate(_ preset: CategoryPreset) {
        guard !activatingPresetKeys.contains(preset.key) else { return }
        activatingPresetKeys.insert(preset.key)

        Task {
            do {
                let activated = try await store.activateCategoryPreset(preset)
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedCategoryID = activated.id
                }
                dismiss()
            } catch {
                errorMessage = AppLocalization.string("category.activateError")
            }
            activatingPresetKeys.remove(preset.key)
        }
    }

    private func finishCreatedCategory() {
        guard let pendingCreatedCategoryID else { return }
        self.pendingCreatedCategoryID = nil
        selectedCategoryID = pendingCreatedCategoryID
        dismiss()
    }

    private func normalizedDisplayName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
