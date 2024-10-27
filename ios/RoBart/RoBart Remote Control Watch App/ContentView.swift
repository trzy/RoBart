//
//  ContentView.swift
//  RoBart Remote Control Watch App
//
//  Created by Bart Trzynadlowski on 10/26/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject var audioRecorder: AudioRecorder
    @StateObject var _iPhone = WatchConnectivityManager.shared

    var body: some View {
        NavigationView {
            VStack {
                if !_iPhone.isConnected {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .imageScale(.large)
                            .foregroundColor(.yellow)
                        Text("Not connected to RoBart!")
                            .padding()
                            .font(.footnote)
                    }
                }
                Button(action: toggleRecording) {
                    Image(systemName: audioRecorder.isRecording ? "record.circle.fill" : "record.circle")
                        .imageScale(.large)
                        .foregroundStyle(.red)
                    Text(audioRecorder.isRecording ? "Stop" : "Record")
                }
            }
            .navigationTitle("RoBart")
            /*
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    NavigationLink {
                        VStack {}
                    } label: {
                        Image(systemName: "gear")
                            .imageScale(.large)
                        Text("Settings")
                            .padding()
                    }
                }
            }
            */
            .padding()
        }
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            let finalChunkNumber = audioRecorder.stopRecording()
            let msg = WatchAudioMessage(chunkNumber: Int32(finalChunkNumber), finished: true, samples: Data())
            _iPhone.sendMessage(key: .audio, value: msg)
        } else {
            audioRecorder.startRecording(onAudioRecorded)
        }
    }

    private func onAudioRecorded(chunkNumber: Int, samples: Data) {
        let msg = WatchAudioMessage(chunkNumber: Int32(chunkNumber), finished: false, samples: samples)
        _iPhone.sendMessage(key: .audio, value: msg)
    }
}

#Preview {
    ContentView(audioRecorder: AudioRecorder())
}
