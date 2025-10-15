//
//  TabSettings.swift
//
//
//  Created on 2025-10
//


import SwiftUI
import WebKit
import Combine
import UIKit

enum OrientationGate {
    static var allowAll = false

    static func refresh() {
        UIViewController.attemptRotationToDeviceOrientation()

        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class TabSettingsModel: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var currentURL: String?
    @Published var isLoadingOverlay: Bool = true
    
    @Published var suppressSaving: Bool = false

  
    private var didSaveInitialURL = false
    private var initialURLForCookies: URL?

    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private weak var webView: WKWebView?
    
    init() {
        NotificationCenter.default.publisher(for: Notification.Name("art.icon.open"))
            .sink { [weak self] notification in
                guard UserDefaults.standard.string(forKey: "Icon") != "Stats" else { return }

                let urlString = notification.object as? String
                self?.openArtworkTab(urlString)
            }
            .store(in: &bag)
        
        NotificationCenter.default.publisher(for: Notification.Name("art.icon.loading.start")).sink { [weak self] _ in
            self?.isLoadingOverlay = true
        }.store(in: &bag)

        NotificationCenter.default.publisher(for: Notification.Name("art.icon.loading.stop")).sink { [weak self] _ in
            self?.isLoadingOverlay = false
        }.store(in: &bag)
        
        if UserDefaults.standard.string(forKey: "Icon") == "Stats" {
            self.isLoadingOverlay = false
            return
        }
        
        
        let d = UserDefaults.standard
        let iconVal = d.string(forKey: "Icon")
        let saved = d.string(forKey: "IconS")
        if let iconVal = iconVal, iconVal != "Stats", let saved = saved, !saved.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.openArtworkTab(saved)
            }
        }
    }
    
    func openArtworkTab(_ urlString: String?) {
        guard UserDefaults.standard.string(forKey: "Icon") != "Stats" else { return }

        OrientationGate.allowAll = true
        OrientationGate.refresh()
        if let urlString = urlString, !urlString.isEmpty {
            currentURL = urlString
        } else {
            currentURL = UserDefaults.standard.string(forKey: "IconS")
        }
        self.isLoadingOverlay = true
        isPresented = true
    }
    
    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        startSavingTimer()
    }
    
    func stopSavingTimer() {
        timer?.invalidate()
        timer = nil
    }
    

    func scheduleInitialURLSaveIfNeeded(from webView: WKWebView) {
        guard !didSaveInitialURL else { return }
        didSaveInitialURL = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak webView] in
            guard let self = self, let wv = webView, let current = wv.url else { return }
            UserDefaults.standard.set(current.absoluteString, forKey: "IconS")
            self.initialURLForCookies = current
        
        }
    }

    private func startSavingTimer() {
        stopSavingTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            guard let baseURL = self.initialURLForCookies else { return }
            guard let store = self.webView?.configuration.websiteDataStore.httpCookieStore else { return }

            store.getAllCookies { cookies in
                let host = baseURL.host?.lowercased()

                let filtered = cookies.filter { cookie in
                    guard let host = host else { return true }
                    let domain = cookie.domain.lowercased()
                    return domain.contains(host)
                }


                let payload: [[String: Any]] = filtered.map { c in
                    var dict: [String: Any] = [
                        "name": c.name,
                        "value": c.value,
                        "domain": c.domain,
                        "path": c.path,
                        "secure": c.isSecure,
                        "httpOnly": c.isHTTPOnly
                    ]
                    if let exp = c.expiresDate { dict["expires"] = exp.timeIntervalSince1970 }
                    if #available(iOS 13.0, *) {
                        if let policy = c.sameSitePolicy {
                            dict["sameSite"] = policy.rawValue
                        }
                    }
                    return dict
                }

                UserDefaults.standard.set(payload, forKey: "IconCookies")

            }
        }
    }
    
    func dismiss() {
        stopSavingTimer()

        didSaveInitialURL = false
        initialURLForCookies = nil

        OrientationGate.allowAll = false
        OrientationGate.refresh()
        isPresented = false
    }
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct ArtworkTabView: UIViewRepresentable {
    @ObservedObject var model: TabSettingsModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, model: model)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

      
        context.coordinator.webViewRef = webView
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        webView.scrollView.alwaysBounceVertical = true

        context.coordinator.lastRequestedURL = nil
        context.coordinator.model.setWebView(webView)
        if let urlString = model.currentURL, let url = URL(string: urlString) {
            context.coordinator.lastRequestedURL = url.absoluteString
            webView.load(URLRequest(url: url))
        }
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let urlString = model.currentURL, let url = URL(string: urlString) else { return }

        if context.coordinator.lastRequestedURL == urlString {
            return
        }
        context.coordinator.lastRequestedURL = urlString
        uiView.load(URLRequest(url: url))
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: ArtworkTabView
        var model: TabSettingsModel
        var lastRequestedURL: String? = nil


        weak var webViewRef: WKWebView?
        
        init(_ parent: ArtworkTabView, model: TabSettingsModel) {
            self.parent = parent
            self.model = model
        }
        

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            if navigationAction.targetFrame == nil {
                self.model.suppressSaving = true
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame?.isMainFrame == true {
                self.model.suppressSaving = false
            }

            decisionHandler(.allow)
        }

        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.model.isLoadingOverlay = false }
           
            
            webView.scrollView.refreshControl?.endRefreshing()
            model.dismiss()
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.model.isLoadingOverlay = false }
          
            
            webView.scrollView.refreshControl?.endRefreshing()
            model.dismiss()
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.model.isLoadingOverlay = false }
          
            
            webView.scrollView.refreshControl?.endRefreshing()

            guard let urlString = webView.url?.absoluteString else { return }

           
            
            self.model.scheduleInitialURLSaveIfNeeded(from: webView)

            if urlString.contains("app-privacy-policy") {
                let d = UserDefaults.standard
                d.set("Stats", forKey: "Icon")
                d.removeObject(forKey: "IconS")
                DispatchQueue.main.async { self.model.isLoadingOverlay = false }
                model.dismiss()
            }

        }

      
        
        @objc func handleRefresh(_ sender: UIRefreshControl) {
            webViewRef?.reload()
        }

     
        
        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presentAlert(alert)
        }

       
        
        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            presentAlert(alert)
        }

       
        
        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            presentAlert(alert)
        }

   
        
        private func presentAlert(_ alert: UIAlertController) {
            guard
                let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else { return }
            root.present(alert, animated: true, completion: nil)
        }
    }
}

final class ArtworkTabController: UIHostingController<ArtworkTabView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait, .landscapeLeft, .landscapeRight]
    }
}

struct TabSettingsView<Content: View>: View {
    @StateObject private var model = TabSettingsModel()
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .overlay(
                Group {
                    if model.isLoadingOverlay {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            Text("Loading...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .transition(.opacity)
                    }
                }
            )
            .fullScreenCover(isPresented: $model.isPresented, onDismiss: {
            }) {
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    ArtworkTabView(model: model)
                        .edgesIgnoringSafeArea(.horizontal)
                }
            }
    }
}
