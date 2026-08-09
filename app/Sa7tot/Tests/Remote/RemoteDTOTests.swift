import Foundation
import XCTest

final class RemoteDTOTests: XCTestCase {
    func testBootstrapFixtureDecodesBackendContractsAndMinorUnitMoney() throws {
        let bootstrap = try RemoteJSON.decoder().decode(RemoteBootstrapDTO.self, from: Data(bootstrapFixture.utf8))

        XCTAssertEqual(bootstrap.accounts.first?.openingBalance, RemoteMoney(minorUnits: 79800, currencyCode: "EUR", exponent: 2))
        let createdAt = try XCTUnwrap(bootstrap.accounts.first?.createdAt)
        XCTAssertEqual(createdAt.timeIntervalSince1970, 1786183200, accuracy: 1)
        XCTAssertEqual(bootstrap.categories.first?.iconIdentifier, "fork.knife")
        XCTAssertEqual(bootstrap.subscriptionSummary.nextBillingDate, try RemoteDateOnly(isoString: "2026-08-15"))
    }

    func testMovimentiFixturePreservesTransferAndSubscriptionMetadata() throws {
        let page = try RemoteJSON.decoder().decode(RemoteMovimentiPageDTO.self, from: Data(movimentiFixture.utf8))
        let movement = try XCTUnwrap(page.days.first?.movements.first)

        XCTAssertEqual(movement.kind, .transfer)
        XCTAssertEqual(movement.amount, RemoteMoney(minorUnits: 200000, currencyCode: "EUR", exponent: 2))
        XCTAssertEqual(movement.localDay, try RemoteDateOnly(isoString: "2026-08-08"))
        XCTAssertEqual(movement.transfer?.sourceAccountName, "Conto principale")
        XCTAssertEqual(movement.transfer?.destinationAccountName, "Test")
        XCTAssertEqual(movement.subscription?.serviceID, "netflix")
    }

    func testFinancialPayloadsKeepCurrencyAmountsInMinorUnits() throws {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let payload = RemoteTransactionCreatePayload(
            kind: .expense,
            accountID: accountID,
            amountMinor: 2500,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: Date(timeIntervalSince1970: 1_786_183_200)
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]

        XCTAssertEqual(object?["amount_minor"] as? Int, 2500)
        XCTAssertEqual(object?["currency_exponent"] as? Int, 2)
        XCTAssertEqual(object?["currency_code"] as? String, "EUR")
    }

    func testRecurrenceContractsDecodeAndCreatePayloadUsesRemoteDateOnly() throws {
        let ruleJSON = """
        {
          "id":"00000000-0000-0000-0000-000000000050",
          "user_id":"00000000-0000-0000-0000-000000000001",
          "account_id":"00000000-0000-0000-0000-000000000010",
          "category_id":"00000000-0000-0000-0000-000000000020",
          "kind":"expense",
          "amount_minor":1299,
          "currency_code":"EUR",
          "currency_exponent":2,
          "title":"Affitto",
          "note":"Affitto",
          "merchant":null,
          "cadence":"monthly",
          "cadence_interval":1,
          "anchor_date":"2026-08-01",
          "next_occurrence_date":"2026-09-01",
          "status":"active",
          "created_at":"2026-08-01T10:00:00Z",
          "updated_at":"2026-08-01T10:00:00Z"
        }
        """
        let rule = try RemoteJSON.decoder().decode(RemoteRecurrenceRuleDTO.self, from: Data(ruleJSON.utf8))
        XCTAssertEqual(rule.amountMinor, 1299)
        XCTAssertEqual(rule.cadence, .monthly)
        XCTAssertEqual(rule.anchorDate, try RemoteDateOnly(isoString: "2026-08-01"))

        let payload = RemoteRecurrenceCreatePayload(
            accountID: rule.accountID,
            categoryID: rule.categoryID,
            kind: .expense,
            amountMinor: 1299,
            currencyCode: "EUR",
            currencyExponent: 2,
            title: "Affitto",
            cadence: .monthly,
            anchorDate: try RemoteDateOnly(isoString: "2026-08-01")
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertEqual(object?["amount_minor"] as? Int, 1299)
        XCTAssertEqual(object?["anchor_date"] as? String, "2026-08-01")
        XCTAssertEqual(object?["cadence"] as? String, "monthly")
    }

    func testUpcomingDTODiscriminatesTransactionsFromRecurrenceProjections() throws {
        let json = """
        {
          "account":{"id":"00000000-0000-0000-0000-000000000010","name":"Conto principale","currency_code":"EUR"},
          "items":[
            {"kind":"recurrence","effective_date":"2026-09-01","rule_id":"00000000-0000-0000-0000-000000000050","scheduled_date":"2026-09-01","account":{"id":"00000000-0000-0000-0000-000000000010","name":"Conto principale","currency_code":"EUR"},"category":null,"transaction_kind":"expense","amount_minor":1299,"currency_code":"EUR","currency_exponent":2,"title":"Affitto","note":null,"merchant":null,"cadence":"monthly","cadence_interval":1}
          ]
        }
        """
        let response = try RemoteJSON.decoder().decode(RemoteUpcomingResponseDTO.self, from: Data(json.utf8))
        XCTAssertEqual(response.items.count, 1)
        guard case let .recurrence(item) = response.items[0] else {
            return XCTFail("Expected a recurrence projection")
        }
        XCTAssertEqual(item.scheduledDate, try RemoteDateOnly(isoString: "2026-09-01"))
        XCTAssertEqual(item.amountMinor, 1299)
    }

    func testBudgetSummaryDecodesMinorUnitsAndCalculatedValues() throws {
        let json = """
        {
          "main": {
            "id":"00000000-0000-0000-0000-000000000040",
            "amount_minor":100000,
            "spent_minor":1250,
            "remaining_minor":98750,
            "progress":0.0125,
            "currency_code":"EUR",
            "currency_exponent":2,
            "period_type":"month",
            "period_start":"2026-08-01",
            "period_end":"2026-09-01",
            "created_at":"2026-08-01T10:00:00Z",
            "updated_at":"2026-08-01T10:00:00Z"
          },
          "categories": []
        }
        """
        let summary = try RemoteJSON.decoder().decode(RemoteBudgetSummaryDTO.self, from: Data(json.utf8))

        XCTAssertEqual(summary.main?.amountMinor, 100000)
        XCTAssertEqual(summary.main?.spentMinor, 1250)
        XCTAssertEqual(summary.main?.remainingMinor, 98750)
        XCTAssertEqual(summary.main?.periodStart, try RemoteDateOnly(isoString: "2026-08-01"))
        XCTAssertEqual(summary.main?.periodType, .month)
    }

    private let bootstrapFixture = """
    {
      "profile": {"user_id":"00000000-0000-0000-0000-000000000001","locale":"it-IT","timezone":"Europe/Rome","default_currency_code":"EUR"},
      "accounts": [{"id":"00000000-0000-0000-0000-000000000010","user_id":"00000000-0000-0000-0000-000000000001","name":"Conto principale","type":"bank","currency_code":"EUR","currency_exponent":2,"opening_balance_minor":79800,"icon_name":"building.columns","color":"blue","wallet_label":null,"is_archived":false,"sort_order":0,"created_at":"2026-08-08T10:00:00Z","updated_at":"2026-08-08T10:00:00.123Z"}],
      "categories": [{"id":"00000000-0000-0000-0000-000000000020","user_id":"00000000-0000-0000-0000-000000000001","name":"Cibo","income":false,"icon_identifier":"fork.knife","color":"orange","sort_order":0,"deleted_at":null,"created_at":"2026-08-08T10:00:00Z","updated_at":"2026-08-08T10:00:00Z"}],
      "subscription_summary": {"active_count":1,"paused_count":0,"next_billing_date":"2026-08-15"}
    }
    """

    private let movimentiFixture = """
    {
      "account":{"id":"00000000-0000-0000-0000-000000000010","name":"Conto principale","currency_code":"EUR","currency_exponent":2,"balance_minor":79800},
      "summary":{"income_minor":100000,"expenses_minor":20200},
      "days":[{"day":"2026-08-08","subtotal_minor":-200000,"movements":[{"id":"00000000-0000-0000-0000-000000000030","user_id":"00000000-0000-0000-0000-000000000001","kind":"transfer","account_id":"00000000-0000-0000-0000-000000000010","destination_account_id":"00000000-0000-0000-0000-000000000011","amount_minor":200000,"currency_code":"EUR","currency_exponent":2,"occurred_at":"2026-08-08T12:00:00.456Z","local_day":"2026-08-08","title":"Trasferimento","effective_amount_minor":-200000,"category":null,"transfer":{"source_account_id":"00000000-0000-0000-0000-000000000010","source_account_name":"Conto principale","destination_account_id":"00000000-0000-0000-0000-000000000011","destination_account_name":"Test"},"subscription":{"id":null,"service_id":"netflix","display_name":"Netflix"},"note":null,"merchant":null,"origin":"manual","review_status":"confirmed","external_reference":null,"created_at":"2026-08-08T12:00:00Z","updated_at":"2026-08-08T12:00:00Z"}]}],
      "next_cursor":null
    }
    """
}
