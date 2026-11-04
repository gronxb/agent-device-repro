import UIKit

// Minimal UIKit app for UIScreenEdgePanGestureRecognizer.
//
// Edge screen:   "edge: N" counts `.began` of one UIScreenEdgePanGestureRecognizer.
//                "pan: N" counts a plain UIPanGestureRecognizer on the same view, to show
//                that the touch reached the app.
//                "last: ..." shows the first touch of the last attempt, its private
//                `UITouch._edgeType`, and the edge recognizer's states.
// Launch flags:  -edges right    watch the right edge instead of the left edge.
//                -nav YES        show a UINavigationController with one pushed screen instead.
//                -contentPop NO  with -nav YES, disable the iOS 26+ full-content pop gesture,
//                                so only the edge pop gesture can pop the screen.

final class TracingEdgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer {
  var onTouchBegan: ((UITouch) -> Void)?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if let touch = touches.first { onTouchBegan?(touch) }
    super.touchesBegan(touches, with: event)
  }
}

final class EdgeViewController: UIViewController, UIGestureRecognizerDelegate {
  private let edgeLabel = UILabel()
  private let panLabel = UILabel()
  private let lastLabel = UILabel()
  private var edgeCount = 0
  private var panCount = 0
  private var touchTrace = "none"
  private var stateTrace: [String] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    let title = UILabel()
    title.text = "Edge pan repro"
    title.font = .boldSystemFont(ofSize: 24)
    edgeLabel.font = .systemFont(ofSize: 20)
    panLabel.font = .systemFont(ofSize: 20)
    lastLabel.font = .systemFont(ofSize: 14)
    lastLabel.numberOfLines = 0
    lastLabel.textAlignment = .center
    render()

    let stack = UIStackView(arrangedSubviews: [title, edgeLabel, panLabel, lastLabel])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
    ])

    let edge = TracingEdgePanGestureRecognizer(target: self, action: #selector(edgeChanged(_:)))
    edge.edges = UserDefaults.standard.string(forKey: "edges") == "right" ? .right : .left
    edge.onTouchBegan = { [weak self, unowned edge] touch in
      self?.touchBegan(touch, recognizer: edge)
    }
    view.addGestureRecognizer(edge)

    let pan = UIPanGestureRecognizer(target: self, action: #selector(panChanged(_:)))
    pan.delegate = self
    view.addGestureRecognizer(pan)
  }

  private func touchBegan(_ touch: UITouch, recognizer: UIGestureRecognizer) {
    let x = touch.location(in: view).x
    touchTrace = String(format: "touch x=%.1f", x) + Self.edgeTypeDescription(touch)
    stateTrace = []
    render()
    // A recognizer that fails never calls its action, so read its state after the swipe.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak recognizer] in
      guard let self, let recognizer, self.stateTrace.isEmpty else { return }
      self.stateTrace = ["never-began(\(Self.stateName(recognizer.state)))"]
      self.render()
    }
  }

  @objc private func edgeChanged(_ recognizer: UIScreenEdgePanGestureRecognizer) {
    let name = Self.stateName(recognizer.state)
    if stateTrace.last != name { stateTrace.append(name) }
    if recognizer.state == .began { edgeCount += 1 }
    render()
  }

  @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
    guard recognizer.state == .began else { return }
    panCount += 1
    render()
  }

  // The control pan must not block the edge recognizer.
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }

  private func render() {
    edgeLabel.text = "edge: \(edgeCount)"
    panLabel.text = "pan: \(panCount)"
    lastLabel.text = "last: \(touchTrace) states=\(stateTrace.joined(separator: ">"))"
  }

  private static func edgeTypeDescription(_ touch: UITouch) -> String {
    // Private UITouch field, read only for diagnostics.
    guard touch.responds(to: NSSelectorFromString("_edgeType")) else { return "" }
    return " edgeType=\(touch.value(forKey: "_edgeType") ?? "nil")"
  }

  private static func stateName(_ state: UIGestureRecognizer.State) -> String {
    switch state {
    case .possible: "possible"
    case .began: "began"
    case .changed: "changed"
    case .ended: "ended"
    case .cancelled: "cancelled"
    case .failed: "failed"
    @unknown default: "unknown"
    }
  }
}

final class LabelViewController: UIViewController {
  private let text: String

  init(title: String, text: String) {
    self.text = text
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }

  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let label = UILabel()
    label.text = text
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }
}

func makeNavigationRoot() -> UIViewController {
  let navigation = UINavigationController(
    rootViewController: LabelViewController(title: "Root", text: "nav root"))
  navigation.pushViewController(
    LabelViewController(title: "Pushed", text: "nav pushed"), animated: false)
  if UserDefaults.standard.string(forKey: "contentPop") == "NO",
    navigation.responds(to: NSSelectorFromString("interactiveContentPopGestureRecognizer")),
    let contentPop = navigation.value(forKey: "interactiveContentPopGestureRecognizer")
      as? UIGestureRecognizer
  {
    contentPop.isEnabled = false
  }
  return navigation
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController =
      UserDefaults.standard.string(forKey: "nav") == "YES"
      ? makeNavigationRoot() : EdgeViewController()
    window.makeKeyAndVisible()
    self.window = window
  }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
