//
//  SettingsView.swift
//  Moonlight for macOS
//
//  Created by Michael Kenny on 15/1/2024.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct PaneCell: Hashable {
    let title: String
    let symbol: String
    let color: Color
}

let panes: [PaneCell] = [
    PaneCell(title: "Stream", symbol: "airplayvideo", color: .blue),
    PaneCell(title: "Video and Audio", symbol: "video.fill", color: .orange),
    PaneCell(title: "Input", symbol: "keyboard.fill", color: .purple),
    PaneCell(title: "App", symbol: "appclip", color: .pink)
]

struct SettingsView: View {
    @StateObject var settingsModel = SettingsModel()

    @SwiftUI.State private var selectedPane: PaneCell? = panes.first

    var body: some View {
        NavigationView {
            Sidebar(selectedPane: $selectedPane)
            Detail(pane: selectedPane)
                .environmentObject(settingsModel)
        }
        .frame(minWidth: 575, minHeight: 275)
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
            
            settingsModel.loadSettings()
        }
    }
}

struct Sidebar: View {
    @Binding var selectedPane: PaneCell?
    
    var body: some View {
        List(selection: $selectedPane) {
            ForEach(panes, id: \.self) { pane in
                PaneCellView(paneCell: pane)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }
}

struct Detail: View {
    var pane: PaneCell? = nil

    @EnvironmentObject private var settingsModel: SettingsModel

    var body: some View {
        if let pane {
            Group {
                if pane.title == "Stream" {
                    StreamView()
                } else if pane.title == "Video and Audio" {
                    VideoAndAudioView()
                } else if pane.title == "Input" {
                    InputView()
                } else if pane.title == "App" {
                    AppView()
                }
            }
            .environmentObject(settingsModel)
            .navigationSubtitle(pane.title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if let hosts = SettingsModel.hosts {
                        HStack {
                            Text("Profile:")
                            
                            Picker("", selection: $settingsModel.selectedHost) {
                                ForEach(hosts, id: \.self) { host in
                                    if let host {
                                        Text(host.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct PaneCellView: View {
    let paneCell: PaneCell
    
    var body: some View {
        let iconSize = CGFloat(14)
        let containerSize = iconSize + (iconSize / 3)

        HStack(spacing: 6) {
            Image(systemName: paneCell.symbol)
                .adaptiveForegroundColor(.white)
                .font(.callout)
                .frame(width: containerSize, height: containerSize)
                .padding(1)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .foregroundColor(paneCell.color)
                )

            Text(paneCell.title)
        }
    }
}

struct StreamView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    @SwiftUI.State private var showCustomResolutionGroup = false
    @SwiftUI.State private var showCustomFpsGroup = false

    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Resolution and FPS") {
                    FormCell(title: "Resolution", contentWidth: 100, content: {
                        Picker("", selection: $settingsModel.selectedResolution) {
                            ForEach(SettingsModel.resolutions, id: \.self) { resolution in
                                if resolution == .zero {
                                    Text("Custom")
                                } else {
                                    Text(verbatim: resolution.height == 2160 ? "4K" : "\(Int(resolution.height))p")
                                }
                            }
                        }
                    })
                    
                    if showCustomResolutionGroup {
                        Divider()
                        
                        FormCell(title: "Custom Width", contentWidth: 60, content: {
                            TextField("", value: $settingsModel.customResWidth, formatter: NumberOnlyFormatter())
                                .multilineTextAlignment(.trailing)
                        })
                        FormCell(title: "Custom Height", contentWidth: 60, content: {
                            TextField("", value: $settingsModel.customResHeight, formatter: NumberOnlyFormatter())
                                .multilineTextAlignment(.trailing)
                        })
                    }
                    
                    Divider()
                    
                    FormCell(title: "FPS", contentWidth: 100, content: {
                        Picker("", selection: $settingsModel.selectedFps) {
                            ForEach(SettingsModel.fpss, id: \.self) { fps in
                                if fps == .zero {
                                    Text("Custom")
                                } else {
                                    Text("\(fps)")
                                }
                            }
                        }
                    })
                    
                    if showCustomFpsGroup {
                        Divider()
                        
                        FormCell(title: "Custom FPS", contentWidth: 60, content: {
                            TextField("", value: $settingsModel.customFps, formatter: NumberOnlyFormatter())
                                .multilineTextAlignment(.trailing)
                        })
                    }
                }
                
                Spacer()
                    .frame(height: 32)
                
                if #available(macOS 12.0, *) {
                    FormSection(title: "Bitrate") {
                        VStack(alignment: .leading) {
                            let bitrate = SettingsModel.bitrateSteps[Int(settingsModel.bitrateSliderValue)].formatted(FloatingPointFormatStyle())
                            Text("\(bitrate) Mbps")
                                .monospacedDigit()
                            Slider(value: $settingsModel.bitrateSliderValue, in: 0...Float(SettingsModel.bitrateSteps.count - 1), step: 1)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .onAppear {
                func updateCustomResolutionGroup() {
                    showCustomResolutionGroup = settingsModel.selectedResolution == .zero
                }
                func updateCustomFpsGroup() {
                    showCustomFpsGroup = settingsModel.selectedFps == .zero
                }

                updateCustomResolutionGroup()
                updateCustomFpsGroup()
                settingsModel.resolutionChangedCallback = {
                    withAnimation {
                        updateCustomResolutionGroup()
                    }
                }
                settingsModel.fpsChangedCallback = {
                    withAnimation {
                        updateCustomFpsGroup()
                    }
                }
            }
        }
    }
}

struct VideoAndAudioView: View {
    @EnvironmentObject private var settingsModel: SettingsModel

    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Video") {
                    FormCell(title: "Video Codec", contentWidth: 155, content: {
                        Picker("", selection: $settingsModel.selectedVideoCodec) {
                            ForEach(SettingsModel.videoCodecs, id: \.self) { codec in
                                Text(codec)
                            }
                        }
                    })
                    
                    Divider()
                    
                    FormCell(title: "HDR", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.hdr) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })
                    
                    Divider()
                    
                    FormCell(title: "Frame Pacing", contentWidth: 155, content: {
                        Picker("", selection: $settingsModel.selectedPacingOptions) {
                            ForEach(SettingsModel.pacingOptions, id: \.self) { pacingOption in
                                Text(pacingOption)
                            }
                        }
                    })
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Audio") {
                    FormCell(title: "Play Sound on Host", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.audioOnPC) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct InputView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Controller") {
                    FormCell(title: "Multi-Controller Mode", contentWidth: 88, content: {
                        Picker("", selection: $settingsModel.selectedMultiControllerMode) {
                            ForEach(SettingsModel.multiControllerModes, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                    })
                    
                    Divider()
                    
                    FormCell(title: "Rumble Controller", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.rumble) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Buttons") {
                    FormCell(title: "Swap A/B and X/Y Buttons", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.swapButtons) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })
                    
                    Divider()
                    
                    FormCell(title: "Emulate Guide Button", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.emulateGuide) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Drivers") {
                    FormCell(title: "Controller Driver", contentWidth: 72, content: {
                        Picker("", selection: $settingsModel.selectedControllerDriver) {
                            ForEach(SettingsModel.controllerDrivers, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                    })
                    
                    Divider()
                    
                    FormCell(title: "Mouse Driver", contentWidth: 72, content: {
                        Picker("", selection: $settingsModel.selectedMouseDriver) {
                            ForEach(SettingsModel.mouseDrivers, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                    })
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct AppView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Behaviour") {
                    FormCell(title: "Automatically Fullscreen Stream Window", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.autoFullscreen) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })

                    Divider()
                    
                    FormCell(title: "Dim Non-Hovered App Artwork", contentWidth: 0, content: {
                        Toggle(isOn: $settingsModel.dimNonHoveredArtwork) {
                            Text("")
                        }
                        .toggleStyle(.switch)
                    })
                }
                
                Spacer()
                    .frame(height: 32)

                FormSection(title: "App Artwork Dimensions") {
                    FormCell(title: "Artwork Width", contentWidth: 60, content: {
                        TextField("", value: $settingsModel.appArtworkWidth, formatter: NumberOnlyFormatter())
                            .multilineTextAlignment(.trailing)
                    })
                    FormCell(title: "Artwork Height", contentWidth: 60, content: {
                        TextField("", value: $settingsModel.appArtworkHeight, formatter: NumberOnlyFormatter())
                            .multilineTextAlignment(.trailing)
                    })
                }
            }
            
            Spacer()
        }
        .padding()
    }
}


struct FormSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        GroupBox(content: {
            VStack {
                Group {
                    content
                }
                .padding([.top], 1)
            }
            .padding([.top, .bottom], 6)
            .padding([.leading, .trailing], 6)
        }, label: {
            Text(title)
                .font(
                    .system(.body, design: .rounded)
                    .weight(.semibold)
                )
                .padding(.bottom, 6)
        })
    }
}

struct FormCell<Content: View>: View {
    let title: String
    let contentWidth: CGFloat
    let content: Content
    
    init(title: String, contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.contentWidth = contentWidth
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Text(title)
            
            Spacer()

            content
                .if(contentWidth != 0, transform: { view in
                    view
                        .frame(width: contentWidth)
                })
        }
    }
}

extension CGSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        return SettingsView()
    } else {
        return Text("Not supported")
    }
}
