//
//  FilterType.swift
//  Bonsai
//
//  Created by Rafael Soh on 3/6/22.
//

import Foundation

enum FilterType: String, CaseIterable {
    case all = "all entries"
    case type = "by type"
    case day = "by day"
    case week = "by week"
    case month = "by month"
    case category = "by category"
    case recurring
    case upcoming

    var italianTitle: String {
        switch self {
        case .all: return "Tutti i movimenti"
        case .type: return "Per tipo"
        case .day: return "Per giorno"
        case .week: return "Per settimana"
        case .month: return "Per mese"
        case .category: return "Per categoria"
        case .recurring: return "Ricorrenti"
        case .upcoming: return "In arrivo"
        }
    }

    static var imageDictionary: [FilterType: String] = [
        .all: "square.text.square.fill",
        .type: "centsign.circle.fill",
        .day: "d.square.fill",
        .week: "w.square.fill",
        .month: "m.square.fill",
        .category: "circle.grid.2x2.fill",
        .recurring: "repeat.circle.fill",
        .upcoming: "sun.min.fill"
    ]
}
