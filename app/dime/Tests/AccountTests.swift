import XCTest

final class AccountTests: XCTestCase {
    func testAccountTypeRawValuesAndItalianLabels() {
        XCTAssertEqual(AccountType.creditCard.rawValue, "creditCard")
        XCTAssertEqual(AccountType.creditCard.italianName, "Carta di credito")
        XCTAssertTrue(AccountType.creditCard.isCredit)
    }

    func testAssetBalanceIncludesOpeningIncomeAndExpenses() {
        XCTAssertEqual(
            AccountBalanceService.balance(openingBalance: 100, type: .bank, income: 250, expenses: 75),
            275)
    }

    func testCreditBalanceUsesSameMovementArithmeticUntilPaymentWorkflowExists() {
        XCTAssertEqual(
            AccountBalanceService.balance(openingBalance: 500, type: .creditCard, income: 100, expenses: 350),
            250)
    }
}
