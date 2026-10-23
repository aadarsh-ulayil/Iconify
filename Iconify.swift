import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FolderArt {
    static func path(_ r: NSRect, tab: Bool) -> NSBezierPath {
        let p = NSBezierPath()
        let x = r.minX, y = r.minY, w = r.width, h = r.height
        p.move(to: NSPoint(x:x+24,y:y))
        p.line(to:NSPoint(x:x+w-24,y:y)); p.curve(to:NSPoint(x:x+w,y:y+24),controlPoint1:NSPoint(x:x+w,y:y),controlPoint2:NSPoint(x:x+w,y:y))
        p.line(to:NSPoint(x:x+w,y:y+h-24)); p.curve(to:NSPoint(x:x+w-24,y:y+h),controlPoint1:NSPoint(x:x+w,y:y+h),controlPoint2:NSPoint(x:x+w,y:y+h))
        if tab {
            p.line(to:NSPoint(x:x+w*0.43,y:y+h)); p.line(to:NSPoint(x:x+w*0.36,y:y+h+28)); p.line(to:NSPoint(x:x+24,y:y+h+28))
            p.curve(to:NSPoint(x:x,y:y+h+4),controlPoint1:NSPoint(x:x,y:y+h+28),controlPoint2:NSPoint(x:x,y:y+h+28))
        } else {
            p.line(to:NSPoint(x:x+24,y:y+h)); p.curve(to:NSPoint(x:x,y:y+h-24),controlPoint1:NSPoint(x:x,y:y+h),controlPoint2:NSPoint(x:x,y:y+h))
        }
        p.line(to:NSPoint(x:x,y:y+24)); p.curve(to:NSPoint(x:x+24,y:y),controlPoint1:NSPoint(x:x,y:y),controlPoint2:NSPoint(x:x,y:y)); p.close(); return p
    }
    static func render(color: NSColor, photo: NSImage?, sticker: Bool, zoom: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> NSImage {
        let result = NSImage(size:NSSize(width:512,height:512))
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let back = path(NSRect(x:42,y:108,width:428,height:292),tab:true)
        let paper = NSBezierPath(roundedRect:NSRect(x:60,y:113,width:392,height:275),xRadius:15,yRadius:15)
        let front = path(NSRect(x:32,y:85,width:448,height:280),tab:false)
        let bounds = NSRect(x:32,y:85,width:448,height:343)
        func drawPhoto(in target: NSRect, cover: Bool) {
            guard let photo else { return }
            let factor = (cover ? max(target.width/photo.size.width,target.height/photo.size.height) : min(target.width/photo.size.width,target.height/photo.size.height)) * (cover ? max(1,zoom) : zoom)
            let size = NSSize(width:photo.size.width*factor,height:photo.size.height*factor)
            let dx = cover ? min(max(offsetX,-(size.width-target.width)/2),(size.width-target.width)/2) : offsetX
            let dy = cover ? min(max(offsetY,-(size.height-target.height)/2),(size.height-target.height)/2) : offsetY
            photo.draw(in:NSRect(x:target.midX-size.width/2+dx,y:target.midY-size.height/2+dy,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1)
        }
        // One continuous crop spans all three layers, including the tab.
        for (index, layer) in [back,paper,front].enumerated() {
            NSGraphicsContext.saveGraphicsState()
            layer.addClip()
            color.setFill(); layer.fill()
            if photo != nil && !sticker {
                drawPhoto(in:bounds,cover:true)
                if index < 2 { NSColor.black.withAlphaComponent(index == 0 ? 0.14 : 0.07).setFill(); layer.fill() }
            } else if index == 2 {
                drawPhoto(in:NSRect(x:138,y:122,width:236,height:206),cover:false)
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(index == 2 ? 0.30 : 0.20).setStroke()
            layer.lineWidth = 1.5; layer.stroke()
        }
        result.unlockFocus(); return result
    }
}

@MainActor final class Studio: ObservableObject {
    @Published var folders: [URL] = []
    let color = Color(white:0.38)
    @Published var showingDefault = false
    @Published var photo: NSImage?
    @Published var photoName = ""
    @Published var sticker = false
    @Published var zoom: Double = 1
    @Published var offsetX: Double = 0
    @Published var offsetY: Double = 0
    @Published var status = "Choose a folder to get started."
    @Published var error: String?
    func clampCrop() {
        guard !sticker, let photo else { return }
        zoom = max(1, min(4, zoom))
        let factor = max(448/photo.size.width,343/photo.size.height) * zoom
        offsetX = min(max(offsetX,-(photo.size.width*factor-448)/2),(photo.size.width*factor-448)/2)
        offsetY = min(max(offsetY,-(photo.size.height*factor-343)/2),(photo.size.height*factor-343)/2)
    }
    var icon: NSImage { showingDefault ? NSWorkspace.shared.icon(for: .folder) : FolderArt.render(color:NSColor(color),photo:photo,sticker:sticker,zoom:zoom,offsetX:offsetX,offsetY:offsetY) }
    func chooseFolders() {
        let p = NSOpenPanel(); p.title = "Choose folders to customize"; p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        if p.runModal() == .OK { folders = p.urls; status = "Ready to customize \(folders.count == 1 ? folders[0].lastPathComponent : "\(folders.count) folders")." }
    }
    @discardableResult func acceptDrop(_ urls: [URL]) -> Bool {
        let directories = urls.filter {
            let values = try? $0.resourceValues(forKeys:[.isDirectoryKey,.isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }
        if !directories.isEmpty {
            var seen = Set<URL>()
            folders = directories.filter { seen.insert($0).inserted }
            status = "Ready to customize \(folders.count) folder\(folders.count == 1 ? "" : "s")."
        }
        let images = urls.filter {
            guard (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true else { return false }
            return NSImage(contentsOf:$0) != nil
        }
        if let image = images.first { loadPhoto(image) }
        if directories.isEmpty && images.isEmpty {
            error = "Drop a folder or image from Finder. Apps and other file types aren’t supported."
            return false
        }
        if images.count > 1 { status = "Loaded the first image. Drop another image to replace it." }
        return true
    }
    func importPhoto() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.image]; p.title = "Import folder artwork"
        if p.runModal() == .OK, let url = p.url { loadPhoto(url) }
    }
    func loadPhoto(_ url: URL) {
        guard let img = NSImage(contentsOf:url), img.size.width > 0, img.size.height > 0 else { error = "This image couldn’t be opened. Try a PNG, JPEG, TIFF, or HEIC image."; return }
        showingDefault = false; photo = img; photoName = url.lastPathComponent; zoom = 1; offsetX = 0; offsetY = 0
    }
    func apply() {
        showingDefault = false
        let rendered = icon
        let failed = folders.filter { !NSWorkspace.shared.setIcon(rendered,forFile:$0.path,options:[]) }
        if failed.isEmpty { status = "Icon applied to \(folders.count) folder\(folders.count == 1 ? "" : "s")." }
        else { error = "Couldn’t change: \(failed.map(\.lastPathComponent).joined(separator:", ")). Check that you have permission to modify these folders." }
    }
    func restore() {
        let alert = NSAlert(); alert.messageText = "Restore the default folder icon?"; alert.informativeText = "This removes any custom icon from the selected folders, including icons set by other apps. Folder contents stay untouched."; alert.addButton(withTitle:"Restore Default"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let failed = folders.filter { !Self.restoreDefault(at: $0) }
        if failed.isEmpty {
            photo = nil; photoName = ""; zoom = 1; offsetX = 0; offsetY = 0
            showingDefault = true
            status = "Default folder icons restored."
        } else { error = "Couldn’t restore: \(failed.map(\.lastPathComponent).joined(separator:", ")). Check folder permissions." }
    }
    static func restoreDefault(at url: URL) -> Bool {
        guard NSWorkspace.shared.setIcon(nil, forFile:url.path, options:[]) else { return false }
        // Notify Finder of the icon metadata change for both the folder and its listing.
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        NSWorkspace.shared.noteFileSystemChanged(url.deletingLastPathComponent().path)
        return true
    }
    func export() {
        let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "Iconify-icon.png"
        if p.runModal() == .OK, let url = p.url, let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let data = rep.representation(using:.png,properties:[:]) {
            do { try data.write(to:url); status = "PNG icon exported." } catch { self.error = error.localizedDescription }
        }
    }
}

// Keep the utility visible while the user drags files out of Finder.
struct FloatingWindow: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.level = .floating
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.title = "Iconify"
            window.appearance = NSAppearance(named:.darkAqua)
            window.isMovableByWindowBackground = false
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ view: WindowView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var studio = Studio()
    @State private var dragOrigin: CGSize?
    @State private var initialZoom: Double?
    @State private var isDropTarget = false
    @State private var showingAbout = false

    var body: some View {
        VStack(spacing:12) {
            HStack {
                Image("AppLogo").resizable().scaledToFit().frame(width:42,height:42)
                VStack(alignment:.leading,spacing:2) {
                    Text("Iconify").font(.system(size:19,weight:.bold))
                    Text("Drop. Customize. Set.").font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingAbout = true } label: { Image(systemName:"info.circle") }.help("About Iconify")
                Button(action:studio.export) { Image(systemName:"square.and.arrow.up") }.help("Export icon as PNG")
            }
            HStack(spacing:10) {
                Image(systemName:"folder.badge.plus").font(.system(size:24)).foregroundStyle(.primary)
                VStack(alignment:.leading,spacing:3) {
                    Text(studio.folders.isEmpty ? "Drop folders from Finder" : studio.folders.map(\.lastPathComponent).joined(separator:", "))
                        .font(.system(size:12,weight:.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(studio.folders.isEmpty ? "Drop an image here too, or import below" : "\(studio.folders.count) selected · Drop folders to replace")
                        .font(.system(size:10)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Button("Browse",action:studio.chooseFolders).controlSize(.small)
            }.padding(12)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.35),style:StrokeStyle(lineWidth:1,dash:[5,4])))
            Image(nsImage:studio.icon).resizable().interpolation(.high).scaledToFit().frame(width:220,height:220)
                .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0)
                        .onChanged { value in
                            guard studio.photo != nil else { return }
                            if dragOrigin == nil { dragOrigin = CGSize(width:studio.offsetX,height:studio.offsetY) }
                            studio.offsetX = (dragOrigin?.width ?? 0) + value.translation.width * 512 / 220
                            studio.offsetY = (dragOrigin?.height ?? 0) - value.translation.height * 512 / 220
                            studio.clampCrop()
                        }
                        .onEnded { _ in dragOrigin = nil })
                    .simultaneousGesture(MagnificationGesture()
                        .onChanged { amount in
                            if initialZoom == nil { initialZoom = studio.zoom }
                            studio.zoom = min(4,max(studio.sticker ? 0.5 : 1,(initialZoom ?? 1) * amount)); studio.clampCrop()
                        }.onEnded { _ in initialZoom = nil })
                    .overlay {
                        if dragOrigin != nil {
                            Path { p in
                                for fraction in [1.0/3.0,2.0/3.0] {
                                    let x = (32+448*fraction)*220/512
                                    let y = (84+343*fraction)*220/512
                                    p.move(to:CGPoint(x:x,y:84*220/512)); p.addLine(to:CGPoint(x:x,y:427*220/512))
                                    p.move(to:CGPoint(x:32*220/512,y:y)); p.addLine(to:CGPoint(x:480*220/512,y:y))
                                }
                            }.stroke(.white.opacity(0.5),style:StrokeStyle(lineWidth:1,dash:[4,4])).allowsHitTesting(false)
                        }
                    }
                    .onChange(of:studio.sticker) { _ in studio.clampCrop() }

            HStack {
                Button(action:studio.importPhoto) { Label(studio.photo == nil ? "Import image" : "Change image",systemImage:"photo") }
                Spacer()
                if studio.photo != nil {
                    Button { studio.zoom = max(studio.sticker ? 0.5 : 1,studio.zoom-0.15); studio.clampCrop() } label: { Image(systemName:"minus.magnifyingglass") }.help("Zoom out")
                    Button { studio.zoom = min(4,studio.zoom+0.15); studio.clampCrop() } label: { Image(systemName:"plus.magnifyingglass") }.help("Zoom in")
                    Button { studio.zoom = 1; studio.offsetX = 0; studio.offsetY = 0 } label: { Image(systemName:"arrow.counterclockwise") }.help("Reset crop")
                }
            }.controlSize(.small)
            HStack {
                Picker("Image style",selection:$studio.sticker) { Text("Full cover").tag(false); Text("Sticker").tag(true) }.pickerStyle(.segmented).frame(width:180)
                Spacer()
                Text("Drag to crop · Pinch to zoom").font(.system(size:10)).foregroundStyle(.secondary)
            }
            HStack(spacing:12) {
                Button("Restore default",action:studio.restore).disabled(studio.folders.isEmpty)
                Button(action:studio.apply) {
                    Text(studio.folders.count > 1 ? "Set on \(studio.folders.count) folders" : "Set folder icon").fontWeight(.semibold).frame(maxWidth:.infinity)
                }.buttonStyle(.borderedProminent).tint(.gray)
                    .disabled(studio.folders.isEmpty || studio.photo == nil).keyboardShortcut(.return,modifiers:.command)
            }.controlSize(.large)
            Text(studio.status).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center).frame(height:26)
        }
        .padding(20).frame(width:440)
        .background(LinearGradient(colors:[Color(nsColor:.windowBackgroundColor),Color.primary.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing))
        .background(FloatingWindow())
        .tint(.gray)
        .preferredColorScheme(.dark)
        .sheet(isPresented:$showingAbout) { AboutView() }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius:14).strokeBorder(Color.primary,lineWidth:3).background(Color.primary.opacity(0.08)).allowsHitTesting(false)
            }
        }
        .dropDestination(for:URL.self) { urls, _ in studio.acceptDrop(urls) } isTargeted: { isDropTarget = $0 }
        .alert("Iconify",isPresented:Binding(get:{studio.error != nil},set:{ if !$0 { studio.error = nil }})) { Button("OK") { studio.error = nil } } message: { Text(studio.error ?? "") }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing:14) {
            Image("AppLogo").resizable().scaledToFit().frame(width:96,height:96)
            Text("Iconify").font(.system(size:26,weight:.bold))
            Text("Version 1.4").font(.system(size:12)).foregroundStyle(.secondary)
            Text("Your favorite images. Your folders.").font(.system(size:13))
            Divider()
            Text("Created by aadarsh ulayil").font(.system(size:13)).multilineTextAlignment(.center).textSelection(.enabled)
            Link("GitHub · aadarsh-ulayil", destination: URL(string:"https://github.com/aadarsh-ulayil")!).foregroundStyle(.primary).underline()
            Text("Made for macOS. Images stay on your Mac.").font(.system(size:11)).foregroundStyle(.secondary)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }.padding(28).frame(width:320).preferredColorScheme(.dark)
    }
}

@main struct IconifyApp: App {
    var body: some Scene {
        Window("Iconify",id:"main") { ContentView() }
            .windowResizability(.contentSize)
            .defaultPosition(.trailing)
            .commands {
                CommandGroup(replacing:.appInfo) {
                    Button("About Iconify") { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Iconify", .credits:NSAttributedString(string:"Created by aadarsh ulayil\nGitHub: aadarsh-ulayil", attributes:[.link:URL(string:"https://github.com/aadarsh-ulayil")!])]) }
                }
            }
    }
}
