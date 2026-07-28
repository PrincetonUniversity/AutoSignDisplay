//
//  AppIconAssetTests.swift
//  AutoSignDisplayTests
//
//  Guards the completeness of the tvOS icon asset catalog.
//
//  Background: build 3 of 1.0 was rejected on upload with
//
//    ITMS-90709: Invalid Image Asset — The image asset 'App Icon' is missing an
//    image for the background layer with a scale value of '2'.
//
//  The icon generator emitted only 1x for each layer of each imagestack. Xcode
//  builds and runs perfectly happily without the 2x images, and the simulator shows
//  the icon correctly, so nothing catches this locally — it surfaces only after a
//  full CI archive, an upload, and Apple's asynchronous processing. That round trip
//  is expensive enough to be worth a test that runs in milliseconds.
//
//  Apple names only the first missing layer, so a fix that adds 2x to the layer
//  named in the rejection and stops would simply earn the same mail about the next
//  one. These tests check every layer of every stack.
//

import Foundation
import Testing

struct AppIconAssetTests {

    // MARK: - Catalog access

    private static var brandAssets: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AutoSignDisplayTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("AutoSignDisplay/Assets.xcassets")
            .appendingPathComponent("App Icon & Top Shelf Image.brandassets")
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let filename: String
            let scale: String
        }
        let images: [Entry]
    }

    private func manifest(in directory: URL) throws -> Manifest {
        let data = try Data(contentsOf: directory.appendingPathComponent("Contents.json"))
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Pixel dimensions read straight from the PNG's IHDR chunk: an 8-byte
    /// signature, a 4-byte length and the "IHDR" tag, then width and height as
    /// big-endian 32-bit integers. Parsed by hand rather than through UIKit so the
    /// test needs no rendering stack and asserts the bytes Apple will actually read.
    private func pngSize(_ url: URL) throws -> (width: Int, height: Int) {
        let data = try Data(contentsOf: url)
        guard data.count >= 24 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        func bigEndian32(at offset: Int) -> Int {
            (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16)
                | (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
        }
        return (bigEndian32(at: 16), bigEndian32(at: 20))
    }

    private func layerImageset(stack: String, layer: String) -> URL {
        Self.brandAssets
            .appendingPathComponent("\(stack).imagestack")
            .appendingPathComponent("\(layer).imagestacklayer")
            .appendingPathComponent("Content.imageset")
    }

    private static let layers = ["Back", "Middle", "Front"]

    // MARK: - The rejection this file exists for

    @Test func everyHomeScreenIconLayerProvidesBothScales() throws {
        for layer in Self.layers {
            let directory = layerImageset(stack: "App Icon", layer: layer)
            let scales = Set(try manifest(in: directory).images.map(\.scale))

            #expect(
                scales == ["1x", "2x"],
                """
                The '\(layer)' layer of the home-screen App Icon declares scales \
                \(scales.sorted()), but tvOS requires both 1x and 2x. Uploading \
                without them is rejected with ITMS-90709, and Apple names only the \
                first missing layer.
                """
            )
        }
    }

    @Test func homeScreenIconImagesAreTheSizesTVOSExpects() throws {
        for layer in Self.layers {
            let directory = layerImageset(stack: "App Icon", layer: layer)
            for entry in try manifest(in: directory).images {
                let size = try pngSize(directory.appendingPathComponent(entry.filename))
                let expected = entry.scale == "2x" ? (800, 480) : (400, 240)
                #expect(
                    size == expected,
                    """
                    \(layer)/\(entry.filename) is \(size.width)x\(size.height), \
                    expected \(expected.0)x\(expected.1) for \(entry.scale).
                    """
                )
            }
        }
    }

    // MARK: - The App Store icon is deliberately single-scale

    @Test func theAppStoreIconStaysSingleScale() throws {
        for layer in Self.layers {
            let directory = layerImageset(stack: "App Icon - App Store", layer: layer)
            let images = try manifest(in: directory).images

            // Not an oversight: unlike the home-screen icon, this one has no 2x
            // variant in the tvOS specification.
            #expect(
                images.map(\.scale) == ["1x"],
                "The App Store icon's '\(layer)' layer should declare 1x only."
            )
            let size = try pngSize(directory.appendingPathComponent(images[0].filename))
            #expect(size == (1280, 768), "\(layer) is \(size.width)x\(size.height), expected 1280x768.")
        }
    }

    // MARK: - Top shelf

    @Test func topShelfImagesProvideBothScales() throws {
        let cases: [(String, String, (Int, Int))] = [
            ("Top Shelf Image", "TopShelf", (1920, 720)),
            ("Top Shelf Image Wide", "TopShelfWide", (2320, 720)),
        ]

        for (imagesetName, prefix, base) in cases {
            let directory = Self.brandAssets.appendingPathComponent("\(imagesetName).imageset")
            let images = try manifest(in: directory).images
            #expect(
                Set(images.map(\.scale)) == ["1x", "2x"],
                "\(imagesetName) should provide both scales."
            )
            for entry in images {
                let size = try pngSize(directory.appendingPathComponent(entry.filename))
                let expected = entry.scale == "2x" ? (base.0 * 2, base.1 * 2) : base
                #expect(
                    size == expected,
                    """
                    \(prefix) \(entry.scale) is \(size.width)x\(size.height), \
                    expected \(expected.0)x\(expected.1).
                    """
                )
            }
        }
    }

    // MARK: - No manifest may reference a file that is not there

    @Test func everyDeclaredImageExistsOnDisk() throws {
        var checked = 0
        let enumerator = FileManager.default.enumerator(
            at: Self.brandAssets,
            includingPropertiesForKeys: nil
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == "Contents.json" else { continue }
            let directory = url.deletingLastPathComponent()
            // Stack and layer manifests carry no images; only imagesets do.
            guard let images = try? manifest(in: directory).images, !images.isEmpty else { continue }

            for entry in images {
                let file = directory.appendingPathComponent(entry.filename)
                #expect(
                    FileManager.default.fileExists(atPath: file.path),
                    """
                    \(directory.lastPathComponent) declares \(entry.filename) at \
                    \(entry.scale) but the file is missing. A manifest entry without \
                    its file fails at upload, not at build time.
                    """
                )
                checked += 1
            }
        }

        // Back/Middle/Front at two scales, plus three single-scale App Store layers,
        // plus two top-shelf images at two scales each.
        #expect(checked >= 13, "Expected to check at least 13 declared images, saw \(checked).")
    }
}
