import Foundation
import SwiftUI

struct TransactionCategoryMenu: View {
    @Binding var category: Category?
    @Binding var showingCategoryView: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    var body: some View {
        Menu {
            ForEach(categories) { item in
                Button {
                    category = item
                } label: {
                    HStack(spacing: 8) {
                        Label {
                            Text(item.wrappedName)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: CategoryIconPresentation.symbol(for: item.wrappedName))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(CategoryIconPresentation.foreground(for: item.wrappedColour))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Circle()
                            .fill(Color(hex: item.wrappedColour))
                            .frame(width: 8, height: 8)
                        if item == category {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel(item.wrappedName)
            }
            Divider()
            Button {
                showingCategoryView = true
            } label: {
                Label("Modifica categorie", systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 5) {
                if let category {
                    HStack(spacing: 5) {
                        Image(systemName: CategoryIconPresentation.symbol(for: category.wrappedName))
                            .symbolRenderingMode(.monochrome)
                        Text(category.wrappedName)
                            .lineLimit(1)
                    }
                    .foregroundStyle(CategoryIconPresentation.foreground(for: category.wrappedColour))
                } else {
                    Text("Scegli").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Categoria")
        .accessibilityValue(category?.wrappedName ?? "Scegli")
    }

    init(category: Binding<Category?>, showingCategoryView: Binding<Bool>, income: Bool) {
        _categories = FetchRequest<Category>(
            sortDescriptors: [SortDescriptor(\.order, order: .reverse)],
            predicate: NSPredicate(format: "income = %d", income)
        )
        _category = category
        _showingCategoryView = showingCategoryView
    }
}

struct NewCategoryPickerView: View {
    @Binding var category: Category?
    @Binding var showPicker: Bool
    @Binding var showingCategoryView: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(categories) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                category = item
                                showPicker = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                        Image(systemName: CategoryIconPresentation.symbol(for: item.wrappedName))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(CategoryIconPresentation.foreground(for: item.wrappedColour))
                            .font(.title3)
                                    .frame(width: 32)
                                Text(item.wrappedName)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(hex: item.wrappedColour))
                                    .frame(width: 4, height: 22)
                                if item == category {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel(item.wrappedName)
                        .accessibilityValue(item == category ? "Selezionata" : "")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Modifica") {
                        showPicker = false
                        showingCategoryView = true
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    init(
        category: Binding<Category?>?, showPicker: Binding<Bool>, showSheet: Binding<Bool>,
        income: Bool
    ) {
        _categories = FetchRequest<Category>(
            sortDescriptors: [SortDescriptor(\.order, order: .reverse)],
            predicate: NSPredicate(format: "income = %d", income)
        )
        _category = category ?? Binding.constant(nil)
        _showPicker = showPicker
        _showingCategoryView = showSheet
    }
}
