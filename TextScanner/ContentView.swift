import SwiftUI
import Vision
import UIKit
import ImageIO
import PhotosUI
import EventKit

struct DetectedText: Identifiable {
    let id = UUID()
    let box: CGRect          // Vision normalized box (0..1), origin is bottom-left
    let text: String
    let confidence: Float
}

struct ShiftCandidate: Identifiable {
    let id = UUID()
    let date: Date
    let start: Date
    let end: Date
    let sourceText: String   // e.g., "11p-7a"
}

struct ContentView: View {
    // UI state
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showBoxes = true
    @State private var personQuery = "sonu" // <- default

    // OCR results
    @State private var recognizedText = ""
    @State private var capturedImage: UIImage?
    @State private var detections: [DetectedText] = []

    // Parsed shifts
    @State private var shifts: [ShiftCandidate] = []

    // Alerts
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            LinearGradient(colors: [.blue.opacity(0.9), .indigo],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .mask(
                    VStack(spacing: 8) {
                        Text("TextScanner")
                            .font(.system(size: 28, weight: .bold))
                        Text("Capture → Read → Highlight → Add to Calendar")
                            .font(.subheadline).opacity(0.9)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                )
                .frame(height: 92)
                .overlay(VStack { Spacer(); Divider().background(Color.white.opacity(0.15)) })

            // Image & overlays
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                if let image = capturedImage {
                    GeometryReader { geo in
                        ZStack {
                            FittedImage(image: image)
                            if showBoxes {
                                BoundingBoxOverlay(
                                    image: image,
                                    containerSize: geo.size,
                                    normalizedBoxes: detections.map { $0.box },
                                    labels: detections.map { $0.text }
                                )
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("Take or choose a photo to extract text").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 300)
            .padding(.horizontal)
            .padding(.top, 12)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Open Camera", systemImage: "camera")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(.blue).foregroundStyle(.white).cornerRadius(12)
                }
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color(.tertiarySystemFill)).cornerRadius(12)
                }
            }
            .padding(.horizontal).padding(.top, 12)

            // Options + person query
            HStack(spacing: 12) {
                Toggle(isOn: $showBoxes) { Label("Show Highlights", systemImage: "highlighter") }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                TextField("Name in schedule", text: $personQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Find Shifts") { extractShifts(for: personQuery) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Recognized text
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recognized Text").font(.headline)
                    Spacer()
                    Button { UIPasteboard.general.string = recognizedText } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.subheadline)
                    }.disabled(recognizedText.isEmpty)
                }
                ScrollView {
                    Text(recognizedText.isEmpty ? "—" : recognizedText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(minHeight: 90, maxHeight: 160)
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Shifts found
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shifts Found").font(.headline)
                    Spacer()
                    Button("Add All") { addAllShiftsToCalendar() }
                        .disabled(shifts.isEmpty)
                }
                if shifts.isEmpty {
                    Text("No shifts yet. Scan/pick an image, then tap **Find Shifts**.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(shifts) { s in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "calendar.badge.plus").font(.title3).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(Self.rangeString(s.start, s.end)).bold()
                                        Text("“\(s.sourceText)”").font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Add") { addShiftToCalendar(s) }
                                        .buttonStyle(.borderedProminent)
                                }
                                .padding(10)
                                .background(Color(.secondarySystemBackground)).cornerRadius(10)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(image: $capturedImage) { image in handleNewImage(image) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { image in if let image { handleNewImage(image) } }
        }
        .alert(alertTitle, isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
    }

    // MARK: - Flow
    private func handleNewImage(_ image: UIImage) {
        capturedImage = image
        recognizedText = "Processing..."
        detections = []
        shifts = []
        recognizeText(in: image)
    }

    private func recognizeText(in image: UIImage) {
        guard let cgImage = image.cgImage else { recognizedText = "Could not read image."; return }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let request = VNRecognizeTextRequest { req, err in
            if let err = err {
                DispatchQueue.main.async {
                    self.recognizedText = "Vision error: \(err.localizedDescription)"
                    self.detections = []; self.shifts = []
                }
                return
            }
            let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
            let lines = obs.compactMap { $0.topCandidates(1).first?.string }
            let boxes: [DetectedText] = obs.compactMap { o in
                guard let best = o.topCandidates(1).first else { return nil }
                return DetectedText(box: o.boundingBox, text: best.string, confidence: best.confidence)
            }
            DispatchQueue.main.async {
                self.recognizedText = lines.joined(separator: "\n")
                self.detections = boxes
            }
        }
        request.recognitionLanguages = ["en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) }
            catch {
                DispatchQueue.main.async {
                    self.recognizedText = "Failed to perform request: \(error.localizedDescription)"
                    self.detections = []; self.shifts = []
                }
            }
        }
    }

    // MARK: - Shift extraction
    private func extractShifts(for name: String) {
        shifts = []
        guard !detections.isEmpty else { show("No OCR yet", "Scan or choose a photo first."); return }

        // 1) Find column headers like "10-Aug" or "16 Aug"
        let headers = detectDateHeaders(in: detections)
        guard !headers.isEmpty else { show("No Dates Found", "Couldn’t detect date headers like “10-Aug”."); return }

        // 2) Find the row Y-band for the given person (case-insensitive)
        guard let rowBand = findRowBand(for: name, in: detections) else {
            show("Name Not Found", "Couldn’t find “\(name)” in the scan."); return
        }

        // 3) Within that band, collect time cells and map them to nearest date column
        let timeCells = detections.filter { d in
            let cy = d.box.midY
            return cy >= rowBand.minY && cy <= rowBand.maxY && isTimeOrOff(d.text)
        }

        var candidates: [ShiftCandidate] = []
        for d in timeCells {
            guard let col = nearestHeader(toCenterX: d.box.midX, headers: headers) else { continue }
            if let shift = parseShiftCell(d.text, on: col.date) {
                candidates.append(shift)
            }
        }

        // 4) Dedup obvious repeats
        shifts = dedupeShifts(candidates)
        if shifts.isEmpty { show("No Shifts Parsed", "Found the row, but couldn’t parse any times.") }
    }

    // Column header model
    private struct HeaderCol { let centerX: CGFloat; let date: Date }

    private func detectDateHeaders(in dets: [DetectedText]) -> [HeaderCol] {
        let year = Calendar.current.component(.year, from: Date())
        let regex = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[-/ ]\s*([A-Za-z]{3,})"#, options: .caseInsensitive)

        var headers: [HeaderCol] = []
        for d in dets {
            let t = d.text.replacingOccurrences(of: "—", with: "-") // just in case
            if let m = regex.firstMatch(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length)) {
                let ns = t as NSString
                let dayStr = ns.substring(with: m.range(at: 1))
                let monStr = ns.substring(with: m.range(at: 2))
                if let month = monthNumber(from: monStr), let day = Int(dayStr), (1...31).contains(day) {
                    var comps = DateComponents()
                    comps.year = year; comps.month = month; comps.day = day
                    if let date = Calendar.current.date(from: comps) {
                        headers.append(HeaderCol(centerX: d.box.midX, date: date))
                    }
                }
            }
        }
        // Merge near-duplicate columns (same date printed twice)
        headers.sort { $0.centerX < $1.centerX }
        var merged: [HeaderCol] = []
        for h in headers {
            if let last = merged.last, abs(last.centerX - h.centerX) < 0.03 {
                continue
            }
            merged.append(h)
        }
        return merged
    }

    private func monthNumber(from s: String) -> Int? {
        let key = s.lowercased().prefix(3)
        let map = ["jan":1,"feb":2,"mar":3,"apr":4,"may":5,"jun":6,"jul":7,"aug":8,"sep":9,"oct":10,"nov":11,"dec":12]
        return map[String(key)]
    }

    private func findRowBand(for name: String, in dets: [DetectedText]) -> CGRect? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Find the detection whose text contains the name (case-insensitive)
        guard let hit = dets.first(where: { $0.text.lowercased().contains(target) }) else { return nil }
        // Make a horizontal band around that Y with a height based on the row box
        let h = max(hit.box.height * 2.0, 0.05) // widen a bit for safety
        let minY = max(0, hit.box.midY - h/2)
        let maxY = min(1, hit.box.midY + h/2)
        return CGRect(x: 0, y: minY, width: 1, height: maxY - minY)
    }

    private func isTimeOrOff(_ t: String) -> Bool {
        let s = t.replacingOccurrences(of: " ", with: "").lowercased()
        if s == "off" || s == "r-off" || s == "r-off" { return true }
        // patterns like 7a-3p, 3p-11p, 11p-7a, 6:30a-1p
        let regex = try! NSRegularExpression(pattern: #"^\s*\d{1,2}(:\d{2})?\s*[ap](m)?\s*[-–]\s*\d{1,2}(:\d{2})?\s*[ap](m)?\s*$"#, options: .caseInsensitive)
        return regex.firstMatch(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length)) != nil
    }

    private func nearestHeader(toCenterX cx: CGFloat, headers: [HeaderCol]) -> HeaderCol? {
        headers.min(by: { abs($0.centerX - cx) < abs($1.centerX - cx) })
    }

    private func parseShiftCell(_ cell: String, on date: Date) -> ShiftCandidate? {
        let raw = cell.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.contains("off") { return nil }

        // Normalize shorthand like "7a" -> "7:00 AM"
        func parseOne(_ token: String, base: Date) -> Date? {
            let t = token.replacingOccurrences(of: " ", with: "").lowercased()
            let re = try! NSRegularExpression(pattern: #"^(\d{1,2})(?::(\d{2}))?\s*([ap])m?$"#, options: [])
            guard let m = re.firstMatch(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length)) else { return nil }
            let ns = t as NSString
            let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let mm = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) ?? 0 : 0
            let ampm = ns.substring(with: m.range(at: 3))
            var hour = h % 12
            if ampm == "p" { hour += 12 }
            var comps = Calendar.current.dateComponents([.year,.month,.day], from: base)
            comps.hour = hour
            comps.minute = mm
            return Calendar.current.date(from: comps)
        }

        // split "11p-7a"
        let parts = raw.replacingOccurrences(of: "–", with: "-").split(separator: "-").map { String($0) }
        guard parts.count == 2 else { return nil }
        guard let start = parseOne(parts[0], base: date) else { return nil }

        // end may be on next day (e.g., 11p-7a)
        var endBase = date
        if let tmpEnd = parseOne(parts[1], base: date), tmpEnd < start {
            endBase = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        guard let end = parseOne(parts[1], base: endBase) else { return nil }

        return ShiftCandidate(date: date, start: start, end: end, sourceText: cell)
    }

    private func dedupeShifts(_ arr: [ShiftCandidate]) -> [ShiftCandidate] {
        var out: [ShiftCandidate] = []
        for s in arr {
            if !out.contains(where: {
                abs($0.start.timeIntervalSince(s.start)) < 60 &&
                abs($0.end.timeIntervalSince(s.end)) < 60
            }) {
                out.append(s)
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: - Calendar
    private func addAllShiftsToCalendar() {
        guard !shifts.isEmpty else { return }
        requestCalendarAccess { granted in
            guard granted else { self.show("Permission Needed", "Allow calendar access in Settings."); return }
            var saved = 0
            for s in shifts { if self.saveEvent(for: s) { saved += 1 } }
            self.show("Done", "Saved \(saved) shift\(saved == 1 ? "" : "s") to Calendar.")
        }
    }

    private func addShiftToCalendar(_ s: ShiftCandidate) {
        requestCalendarAccess { granted in
            guard granted else { self.show("Permission Needed", "Allow calendar access in Settings."); return }
            let ok = self.saveEvent(for: s)
            self.show(ok ? "Event Added" : "Save Failed",
                      ok ? Self.rangeString(s.start, s.end) : "Could not save event.")
        }
    }

    private func requestCalendarAccess(_ completion: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        store.requestAccess(to: .event) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    private func saveEvent(for s: ShiftCandidate) -> Bool {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "\(personQuery.capitalized) shift"
        event.startDate = s.start
        event.endDate = s.end
        event.notes = "Detected from OCR: \(s.sourceText)"
        guard let cal = store.defaultCalendarForNewEvents ??
                store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else { return false }
        event.calendar = cal
        do { try store.save(event, span: .thisEvent); return true }
        catch { return false }
    }

    // MARK: - Helpers
    private func show(_ title: String, _ msg: String) {
        alertTitle = title; alertMessage = msg; showAlert = true
    }
    private static func rangeString(_ s: Date, _ e: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.doesRelativeDateFormatting = true
        return "\(f.string(from: s)) → \(f.string(from: e))"
    }
}

// Display image aspect-fit
private struct FittedImage: View {
    let image: UIImage
    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let size = image.size
            let scale = min(container.width / size.width, container.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            let x = (container.width - fitted.width) / 2
            let y = (container.height - fitted.height) / 2

            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.width/2 + x, y: fitted.height/2 + y)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        }
    }
}

// Convenience: center points from normalized rects
private extension CGRect {
    var midX: CGFloat { origin.x + width/2 }
    var midY: CGFloat { origin.y + height/2 }
}
// Orientation helper: map UIImage.Orientation -> CGImagePropertyOrientation
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

