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

    var localizedTitle: String {
        switch self {
        case .all: return AppLocalization.string("filter.all")
        case .type: return AppLocalization.string("filter.type")
        case .day: return AppLocalization.string("filter.day")
        case .week: return AppLocalization.string("filter.week")
        case .month: return AppLocalization.string("filter.month")
        case .category: return AppLocalization.string("filter.category")
        case .recurring: return AppLocalization.string("filter.recurring")
        case .upcoming: return AppLocalization.string("filter.upcoming")
        }
    }

    var italianTitle: String { localizedTitle }

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
