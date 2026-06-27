@resultBuilder
public enum QueryItemsBuilder {
  public static func buildBlock(_ components: [QueryItem]...) -> [QueryItem] {
    components.flatMap(\.self)
  }

  public static func buildExpression(_ expression: QueryItem) -> [QueryItem] {
    [expression]
  }

  public static func buildExpression(_ expression: QueryItem?) -> [QueryItem] {
    expression.map { [$0] } ?? []
  }

  public static func buildExpression(_ expression: [QueryItem]) -> [QueryItem] {
    expression
  }

  public static func buildExpression(_ expression: [QueryItem?]) -> [QueryItem] {
    expression.compactMap(\.self)
  }

  public static func buildOptional(_ component: [QueryItem]?) -> [QueryItem] {
    component ?? []
  }

  public static func buildEither(first component: [QueryItem]) -> [QueryItem] {
    component
  }

  public static func buildEither(second component: [QueryItem]) -> [QueryItem] {
    component
  }

  public static func buildArray(_ components: [[QueryItem]]) -> [QueryItem] {
    components.flatMap(\.self)
  }
}

public func QueryItems(@QueryItemsBuilder _ build: () -> [QueryItem]) -> [QueryItem] {
  build()
}
