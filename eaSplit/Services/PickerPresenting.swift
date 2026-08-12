@MainActor
protocol PickerPresenting: AnyObject {
  func show(model: AppModel)
  func dismiss()
}
