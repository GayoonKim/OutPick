import FirebaseFirestore
import Testing
@testable import OutPick

struct FirestoreDocumentIDBoundaryTests {
    @Test func brandDomainUsesPathIDInsteadOfStoredIDField() throws {
        let dto = try Firestore.Decoder().decode(
            BrandDTO.self,
            from: [
                "id": "stored-legacy-id",
                "name": "Boundary Brand"
            ]
        )

        let brand = try dto.toDomain(documentID: "path-brand-id")

        #expect(brand.id == BrandID(value: "path-brand-id"))
        #expect(brand.name == "Boundary Brand")
    }

    @Test func emptyPathDocumentIDFailsDomainMapping() throws {
        let dto = try Firestore.Decoder().decode(
            BrandDTO.self,
            from: ["name": "Boundary Brand"]
        )

        #expect(throws: MappingError.self) {
            try dto.toDomain(documentID: "")
        }
    }

    @Test func seasonWritePayloadDoesNotContainPrimaryDocumentID() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let season = Season(
            id: SeasonID(value: "path-season-id"),
            brandID: BrandID(value: "brand-id"),
            displayTitle: "24 F/W",
            sourceTitle: nil,
            year: 2024,
            term: .fw,
            coverPath: "brands/brand-id/seasons/path-season-id/cover.jpg",
            coverRemoteURL: nil,
            description: "Boundary season",
            tagIDs: [TagID(value: "minimal")],
            tagConceptIDs: ["concept-minimal"],
            status: .published,
            deletionStatus: .active,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: 1,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: nil,
            postCount: 0,
            likeCount: 0,
            createdAt: now,
            updatedAt: now
        )

        let payload = try Firestore.Encoder().encode(
            SeasonWriteDTO.fromDomain(season)
        )

        #expect(payload["id"] == nil)
        #expect(payload["ID"] == nil)
        #expect(payload["displayTitle"] as? String == "24 F/W")
        #expect(payload["tagIDs"] as? [String] == ["minimal"])
    }
}
