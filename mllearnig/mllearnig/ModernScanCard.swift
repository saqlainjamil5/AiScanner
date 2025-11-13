import SwiftUI

struct ModernScanCard: View {
    let scan: ScannedDocument
    let isLatest: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            Group {
                if let thumb = scan.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else if let image = scan.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(scan.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if isLatest {
                        Text("Latest")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 12) {
                    if let date = scan.extracted.dateString {
                        Label(date, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let amount = scan.extracted.totalAmount {
                        Label(amount, systemImage: "dollarsign.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if !scan.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(scan.tags.prefix(3), id: \.self) { tag in
                                TagView(text: tag)
                            }
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
