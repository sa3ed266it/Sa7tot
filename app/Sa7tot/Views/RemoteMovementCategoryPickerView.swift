import SwiftUI

@available(iOS 26.0, *)
struct RemoteMovementCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator

    @Binding var selectedCategoryID: UUID?
    let income: Bool

    @State private var localSelection: UUID?
    @State private var activatingPresetKeys: Set<String> = []
    @State private var errorMessage: String?
    @State private var showingNewCategory = false

    init(selectedCategoryID: Binding<UUID?>, income: Bool) {
        _selectedCategoryID = selectedCategoryID
        self.income = income
        _localSelection = State(initialValue: selectedCategoryID.wrappedValue)
    }

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
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.key("action.finish")) {
                        selectedCategoryID = localSelection
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewCategory) {
            RemoteCategoryEditorView(
                category: nil,
                initialIncome: income,
                onCreated: { createdCategory in
                    guard createdCategory.income == income else {
                        appToastCoordinator.showError(titleKey: "error.mutation.save.title", messageKey: AppLocalization.string("category.saveError"))
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        localSelection = createdCategory.id
                    }
                }
            )
            .environmentObject(store)
            .environmentObject(appToastCoordinator)
        }
        .presentationDetents([.fraction(0.70)])
        .presentationDragIndicator(.visible)
    }

    private func activeCategoryRow(_ category: RemoteCategoryDTO) -> some View {
        Button {
            localSelection = category.id
        } label: {
            HStack(spacing: 12) {
                CategoryIconView(
                    descriptor: CategoryIconPresentation.descriptor(for: category),
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

                if localSelection == category.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(localSelection == category.id ? .isSelected : [])
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
                    Sa7totLoader(size: .compact)
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
                    localSelection = activated.id
                    activatingPresetKeys.remove(preset.key)
                }
            } catch {
                errorMessage = AppLocalization.string("category.activateError")
                activatingPresetKeys.remove(preset.key)
            }
        }
    }

    private func normalizedDisplayName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
