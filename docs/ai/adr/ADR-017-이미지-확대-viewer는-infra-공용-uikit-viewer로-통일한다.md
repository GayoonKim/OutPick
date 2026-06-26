# ADR-017: 이미지 확대 viewer는 Infra 공용 UIKit viewer로 통일한다


상태: accepted

결정:

- Chat, Profile, Lookbook 이미지 확대 화면은 UIKit 기반 `SimpleImageViewerVC`를 공용 viewer 기반으로 사용한다.
- 공용 viewer와 page/source 계약은 `OutPick/Infra/Media/ImageViewer`에 둔다.
- `ImageViewerPage`를 공용 page/source 계약으로 사용한다.
- 기존 `SimpleImageViewerVC.ProgressivePage`는 호출부 호환을 위해 `ImageViewerPage` typealias로 유지한다.
- local-only 이미지는 별도 viewer를 두지 않고 `initialImage`만 가진 `ImageViewerPage`로 연다.
- 이미지 viewer 저장 버튼은 항상 노출한다.
- current page original load는 demand load로 보고 adjacent/bulk warmup보다 우선한다.
- 비디오 viewer 통일은 이 결정 범위에서 제외한다.

이유:

- Chat과 Profile은 이미 `SimpleImageViewerVC` 기반이라 UIKit viewer를 공용화하는 편이 변경 위험이 작다.
- Lookbook SwiftUI 화면도 UIKit wrapper/bridge로 같은 viewer 경험에 연결할 수 있다.
- local-only 이미지만 별도 `LocalImageViewerVC`로 유지하면 닫기, 저장, zoom, 제스처 정책이 계속 갈라진다.
- 30장 이미지 묶음에서는 현재 페이지 original이 주변 prefetch보다 먼저 업그레이드되어야 사용자가 본 이미지 품질이 빠르게 안정된다.

트레이드오프:

- SwiftUI 화면은 UIKit viewer presentation bridge가 필요하다.
- 기존 호출부가 `SimpleImageViewerVC.ProgressivePage`를 계속 참조할 수 있어, 장기적으로는 `ImageViewerPage` 직접 사용으로 천천히 정리할 수 있다.
- current page 우선 스케줄링은 prefetch 적극성을 조금 낮출 수 있다.

재검토 조건:

- Lookbook 전체 media paging, video viewer 통일, interactive percent-driven dismiss까지 포함하는 새 viewer 설계가 필요해진다.
- 공용 viewer가 Chat/Profile/Lookbook 외 도메인에서 더 넓게 쓰이며 UIKit 의존이 SwiftUI 개발 속도를 크게 늦춘다.
