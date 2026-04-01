import HTTPTypes

@resultBuilder
public enum HTTPFieldsBuilder {
  public static func buildBlock(_ components: HTTPFields...) -> HTTPFields {
    var fields = HTTPFields()
    for component in components {
      fields.append(contentsOf: component)
    }
    return fields
  }

  public static func buildExpression(_ expression: HTTPField) -> HTTPFields {
    var fields = HTTPFields()
    fields.append(expression)
    return fields
  }

  public static func buildExpression(_ expression: HTTPField?) -> HTTPFields {
    expression.map(buildExpression) ?? HTTPFields()
  }

  public static func buildExpression(_ expression: HTTPFields) -> HTTPFields {
    expression
  }

  public static func buildOptional(_ component: HTTPFields?) -> HTTPFields {
    component ?? HTTPFields()
  }

  public static func buildEither(first component: HTTPFields) -> HTTPFields {
    component
  }

  public static func buildEither(second component: HTTPFields) -> HTTPFields {
    component
  }

  public static func buildArray(_ components: [HTTPFields]) -> HTTPFields {
    var fields = HTTPFields()
    for component in components {
      fields.append(contentsOf: component)
    }
    return fields
  }
}

public func HeaderFields(@HTTPFieldsBuilder _ build: () -> HTTPFields) -> HTTPFields {
  build()
}
