//
//  AppRoute.swift
//  Spot
//
//  Created by Hasan on 01/09/2025.
//


// App/Core/Navigation/Router.swift
import SwiftUI

public enum AppRoute: Hashable {
    case lesionResult(Lesion)
}

public final class Router: ObservableObject {
    @Published public var path = NavigationPath()
    static let shared = Router()
   // public init() {}

    public func push(_ route: AppRoute) { path.append(route) }
    public func pop() { if !path.isEmpty { path.removeLast() } }
    public func popToRoot() { path.removeLast(path.count) }
}
