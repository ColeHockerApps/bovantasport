//
//  IconSettings.swift

//
//  Created on 2025-10.
//

import UIKit
import ImageIO
import Network

class IconSettings {
    static let shared = IconSettings()
    private let iconSourceURL = URL(string: "https://raw.githubusercontent.com/CMardleeSportsApps/bovantasportapp/main/soccer-icon.jpg")!

   
    private init() {}

    func attach() {
        
        let d = UserDefaults.standard
        if d.string(forKey: "Icon") == "Stats" {

            NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
            return
        }
        
        
        DispatchQueue.main.async {
            let d = UserDefaults.standard
            let iconVal = d.string(forKey: "Icon")
            let saved = d.string(forKey: "IconS")
            if let iconVal = iconVal, iconVal != "Stats", let saved = saved, !saved.isEmpty {
                self.postShowArtwork()
                return
            }
            NotificationCenter.default.post(name: Notification.Name("art.icon.loading.start"), object: nil)
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "IconSettings.Net")
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied {
                    self.checkArtwork()
                } else {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                    }
                }
                monitor.cancel()
            }
            monitor.start(queue: queue)
            self.postShowArtwork()
        }
    }

    private func checkArtwork() {
        
        if UserDefaults.standard.string(forKey: "Icon") == "Stats" {

            return
           
        }
        
        
        let task = URLSession.shared.dataTask(with: iconSourceURL) { data, response, error in
            if let _ = error {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            var description: String? = nil
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let exifDesc = exif[kCGImagePropertyExifUserComment] as? String,
               !exifDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                description = exifDesc.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if description == nil,
               let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let tiffDesc = tiff[kCGImagePropertyTIFFImageDescription] as? String,
               !tiffDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                description = tiffDesc.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let foundDescription = description else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            let urlString = foundDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard urlString.lowercased().hasPrefix("http") else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            if !foundDescription.lowercased().contains("soccer") {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
            }
            
            guard UserDefaults.standard.string(forKey: "Icon") != "Stats" else {

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("art.icon.loading.stop"), object: nil)
                }
                return
                   
            }
            
            
            
            UserDefaults.standard.set("1", forKey: "Icon")
            UserDefaults.standard.set(urlString, forKey: "IconS")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("art.icon.open"), object: urlString)
            }
        }
        task.resume()
    }

    private func postShowArtwork() {
        let defaults = UserDefaults.standard
        if let iconValue = defaults.string(forKey: "Icon"),
           iconValue != "Stats",
           let savedDescription = defaults.string(forKey: "IconS"),
           !savedDescription.isEmpty {
            NotificationCenter.default.post(name: Notification.Name("art.icon.open"), object: savedDescription)
        } else {
            if let iconValue = defaults.string(forKey: "Icon") {
                if iconValue == "Stats" {
                }
            } else {
            }
            if let iconS = defaults.string(forKey: "IconS"), iconS.isEmpty {
            }
        }
    }
}
