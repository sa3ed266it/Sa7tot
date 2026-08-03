import Foundation
import SwiftUI

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
                                Text(item.wrappedEmoji)
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
