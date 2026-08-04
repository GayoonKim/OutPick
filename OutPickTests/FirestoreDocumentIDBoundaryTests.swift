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

    @Test func brandDTOReadsEveryPersistedDiscoveryStatus() throws {
        let statuses = [
            "idle", "queued", "running", "success", "succeeded",
            "awaitingReview", "correctionRequired", "failed",
            "cancelled", "superseded"
        ]

        for status in statuses {
            let dto = try Firestore.Decoder().decode(
                BrandDTO.self,
                from: [
                    "name": "Discovery Status Brand",
                    "discoveryStatus": status
                ]
            )

            #expect(dto.discoveryStatus?.rawValue == status)
        }
    }

    @Test func seasonDomainUsesPathIDAndReadsMoodIDs() throws {
        let dto = try Firestore.Decoder().decode(
            SeasonDTO.self,
            from: [
                "id": "stored-legacy-id",
                "displayTitle": "24 F/W",
                "description": "",
                "tagIDs": ["minimal"],
                "moodIDs": ["street"],
                "status": "published",
                "assetSyncStatus": "ready",
                "metadataStatus": "confirmed",
                "postCount": 0
            ]
        )

        let season = try dto.toDomain(
            documentID: "path-season-id",
            brandID: BrandID(value: "brand-id")
        )

        #expect(season.id == SeasonID(value: "path-season-id"))
        #expect(season.moodIDs == ["street"])
    }
}
