#if canImport(FoundationModels)
import FoundationModels

/// The model selects a source, never authors power-management instructions.
@available(macOS 26.0, *)
@Generable
struct HelpAnswerSelection {
    @Guide(description: "The number of the guide article that answers the question. Use 0 if none of the articles answer it.", .range(0...20))
    var articleNumber: Int
}
#endif
