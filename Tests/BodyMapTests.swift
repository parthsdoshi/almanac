import Testing
@testable import Occasions

@Suite struct BodyMapTests {
    @Test func everyPlanMuscleHasARegion() {
        let mapped = Set(BodyMapShapes.groups.values.flatMap { $0 })
        let used = Set(WorkoutPlan.allExercises.flatMap(\.muscles))
        #expect(used.subtracting(mapped).isEmpty)
    }

    @Test func sideDeltsLightTheShoulders() {
        #expect(BodyMapShapes.isLit("front-delts", ["Side delts"]))
        #expect(!BodyMapShapes.isLit("rear-delts", ["Side delts"]))
        #expect(!BodyMapShapes.isLit(nil, ["Quads"]))
    }

    @Test func shapesMatchTheWebMap() {
        #expect(BodyMapShapes.front.count == 15)
        #expect(BodyMapShapes.back.count == 16)
        #expect((BodyMapShapes.front + BodyMapShapes.back).allSatisfy { $0.points.count == 4 })
    }
}
