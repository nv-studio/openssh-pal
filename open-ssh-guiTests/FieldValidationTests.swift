import Testing

@Suite("Field validation state")
struct FieldValidationTests {

    @Test("An invalid field exposes the message explaining why")
    func invalidExposesItsMessage() {
        let validation = FieldValidation.invalid("HostName is required")

        #expect(validation.message == "HostName is required")
        #expect(validation.isValid == false)
    }

    @Test("A valid field exposes no message, so valid-with-an-error cannot be rendered")
    func validExposesNoMessage() {
        let validation = FieldValidation.valid

        #expect(validation.message == nil)
        #expect(validation.isValid)
    }
}
