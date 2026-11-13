# 🎹 Piano Go

Ứng dụng **học đàn piano trên iPad** theo phong cách Duolingo: các bài học ngắn, lộ trình mở khóa dần, XP, chuỗi ngày học, tim và ngôi sao.
iPad kết nối với **đàn Bora BX20** (hoặc bất kỳ đàn nào hỗ trợ **Bluetooth MIDI / USB MIDI**). Ứng dụng nghe được bạn đánh phím nào và chấm điểm ngay lập tức.

## Tính năng

| | |
|---|---|
| **Kết nối đàn** | Bluetooth LE MIDI (tự tìm đàn, tự kết nối lại lần sau), bảng kết nối Bluetooth MIDI chuẩn của Apple, hoặc cáp USB. Có ô kiểm tra hiện nốt vừa đánh và lực nhấn. |
| **Lộ trình học** | 8 chương, 44 bài: làm quen bàn phím → vị trí 5 ngón → đọc nốt khóa Sol → nhịp điệu → phím đen (thăng/giáng) → hợp âm → tay trái & khóa Fa → gam & bài hát. |
| **Dạng bài tập** | Giới thiệu nốt mới, tìm phím theo tên, đọc nốt trên khuông rồi đánh, chọn tên nốt (trắc nghiệm, có thể trả lời bằng cách đánh đàn), nghe và đánh lại, đánh giai điệu (chế độ chờ), đánh hợp âm (giữ cùng lúc), gõ theo tiết tấu với máy đếm nhịp, câu hỏi lý thuyết. |
| **Kiểu Duolingo** | 5 tim mỗi bài, làm sai thì bài tập được đưa lại cuối hàng, thanh tiến độ, banner đúng/sai, màn hình hoàn thành với XP, độ chính xác và 1–3 sao, chuỗi ngày học, mục tiêu XP mỗi ngày, cấp độ. |
| **Bài hát** | 13 bài (Kìa con bướm vàng, Ngôi sao lấp lánh, Khúc hoan ca, Jingle Bells, Chúc mừng sinh nhật, Für Elise…). Chế độ **Chờ** (đợi bạn đánh đúng) và **Theo nhịp** (khuông nhạc cuộn, chấm Tuyệt/Tốt/Trượt), chỉnh tốc độ, nghe mẫu. |
| **Chơi tự do** | Bàn phím 2–4 quãng tám, nhận diện hợp âm (C, Am, G7, thể đảo…) và quãng, hiện nốt vừa chơi lên khuông, máy đếm nhịp. |
| **Khác** | Bàn phím ảo đa chạm (dùng được khi chưa có đàn), tên nốt Đô Rê Mi / C D E, số ngón tay gợi ý, âm thanh tổng hợp sẵn (không cần file âm thanh), giao diện tiếng Việt. |

## Kết nối đàn Bora BX20

1. Bật đàn, bật **Bluetooth** trên đàn (đèn Bluetooth nhấp nháy).
2. **Không** ghép đôi trong *Cài đặt › Bluetooth* của iPad: Bluetooth MIDI được kết nối ngay trong ứng dụng.
3. Mở Piano Go → bấm **Kết nối đàn** (góc trên bên trái) → chờ tên đàn hiện ra (thường là *BX20*, *BORA*, *Piano* hoặc *BLE‑MIDI*) → **Kết nối**.
4. Đánh thử vài phím: ô **Kiểm tra** hiện tên nốt là đã xong.
   Nếu không thấy đàn, bấm **Bảng kết nối của Apple** (bảng Bluetooth MIDI chuẩn của iOS).

> Đàn đang kết nối với điện thoại hay ứng dụng khác thì hãy ngắt ở đó trước. Có thể dùng cáp USB‑MIDI thay cho Bluetooth.

## Cài lên iPad

### Cách 1: tải file IPA do GitHub Actions build (không cần máy Mac)

1. Vào tab **Actions** của repo → workflow **Build Piano Go** → chọn lần chạy mới nhất (màu xanh) → tải artifact **PianoGo-ipa**.
   Hoặc chạy workflow thủ công (**Run workflow**) và tick *Tạo bản phát hành* để có file `.ipa` trong mục **Releases**.
2. File IPA **chưa được ký**. Cài bằng công cụ sideload quen thuộc: **Sideloadly**, **AltStore**, **TrollStore**, **ESign**…, giống cách cài các IPA tự build khác.

### Cách 2: build bằng Xcode trên máy Mac

```bash
brew install xcodegen
xcodegen generate          # tạo PianoGo.xcodeproj từ project.yml
open PianoGo.xcodeproj
```

Chọn Team của bạn ở *Signing & Capabilities*, cắm iPad và bấm **Run**. Yêu cầu iPadOS 15 trở lên, Xcode 15 trở lên.

## Cấu trúc mã nguồn

```
project.yml                  Cấu hình XcodeGen (target iOS/iPadOS 15+)
App/                         Ứng dụng SwiftUI
  PianoGoApp.swift           Khởi động, nối các service
  Services/
    MIDIManager.swift        CoreMIDI: nhận nốt từ mọi nguồn MIDI (UMP / MIDI 1.0)
    BluetoothMIDI.swift      Tìm & kết nối đàn BLE MIDI (CoreBluetooth) + bảng của Apple
    NoteInput.swift          Gom nốt từ đàn thật và bàn phím ảo
    SynthEngine.swift        Bộ tổng hợp tiếng piano, máy đếm nhịp, âm báo
    AppModel.swift           Tiến độ & cài đặt (lưu UserDefaults)
  Views/                     Lộ trình học, bài học, bài tập, bài hát, chơi tự do, hồ sơ
PianoCore/                   Swift package thuần logic, có unit test
  Pitch, Score               Nốt nhạc, tên Đô Rê Mi, vị trí trên khuông, đọc bản nhạc dạng chữ
  Curriculum, SongLibrary    Giáo trình 8 chương, thư viện bài hát
  Evaluators, LessonSession  Chấm điểm chế độ chờ / theo nhịp, phiên học kiểu Duolingo
  Progress, Theory           XP, chuỗi ngày, nhận diện hợp âm, giải mã MIDI
  MusicGlyphData, SVGPath    Ký hiệu âm nhạc vector (trích từ font Bravura)
```

Chạy kiểm thử phần lõi (macOS hoặc Linux có Swift 5.7+):

```bash
swift test --package-path PianoCore
```

### Thêm bài hát

Bài hát được viết dạng chữ trong `PianoCore/Sources/PianoCore/SongLibrary.swift`:

```swift
Song(id: "mary", title: "Mary có chú cừu non", subtitle: "Dân ca Mỹ", level: 1, tempo: 100,
     score: "E4@3 D4@2 C4@1 D4 | E4 E4 E4:h | ...")
```

`C4` = nốt đen, `:h` nốt trắng, `:w` nốt tròn, `:e` móc đơn, `:s` móc kép, `.` chấm dôi, `C4+E4+G4` hợp âm, `R` dấu lặng, `@3` ngón tay. Unit test tự kiểm tra mỗi ô nhịp có đủ phách.

## Giấy phép bên thứ ba

Ký hiệu âm nhạc lấy từ font **Bravura** © Steinberg Media Technologies GmbH, theo giấy phép SIL Open Font License 1.1 (xem `Licenses/Bravura-OFL.txt`).
