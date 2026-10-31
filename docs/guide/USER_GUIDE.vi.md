# Hướng dẫn sử dụng HyperEdit

<p align="center"><a href="USER_GUIDE.md">English</a> · <a href="USER_GUIDE.ko.md">한국어</a> · <a href="USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="USER_GUIDE.ja.md">日本語</a> · Tiếng Việt · <a href="USER_GUIDE.hi.md">हिन्दी</a> · <a href="USER_GUIDE.de.md">Deutsch</a> · <a href="USER_GUIDE.fr.md">Français</a> · <a href="USER_GUIDE.es.md">Español</a> · <a href="USER_GUIDE.pt.md">Português</a> · <a href="USER_GUIDE.ar.md">العربية</a></p>

HyperEdit là trình soạn thảo văn bản thuần nhanh cho macOS, được xây dựng quanh một tệp ghi chú lớn — loại tệp mà bạn cứ thêm vào suốt nhiều năm. Hướng dẫn này giải thích mọi điều bạn có thể làm với nó, theo thứ tự bạn thường gặp. Phím tắt được viết bằng ký hiệu của Mac: ⌘ Command, ⇧ Shift, ⌥ Option, ⌃ Control.

## Mục lục

1. [Cài đặt và cập nhật](#1-cài-đặt-và-cập-nhật)
2. [Khởi chạy lần đầu](#2-khởi-chạy-lần-đầu)
3. [Ngôn ngữ giao diện](#3-ngôn-ngữ-giao-diện)
4. [Cửa sổ](#4-cửa-sổ)
5. [Chỉnh sửa cơ bản](#5-chỉnh-sửa-cơ-bản)
6. [Tìm và thay thế](#6-tìm-và-thay-thế)
7. [Dấu trang](#7-dấu-trang)
8. [Chế độ cột và đa con trỏ](#8-chế-độ-cột-và-đa-con-trỏ)
9. [Công cụ dòng và văn bản](#9-công-cụ-dòng-và-văn-bản)
10. [Đoạn mẫu](#10-đoạn-mẫu)
11. [Macro](#11-macro)
12. [Thu gọn mã và dấu thanh cuộn](#12-thu-gọn-mã-và-dấu-thanh-cuộn)
13. [Chia đôi khung soạn thảo](#13-chia-đôi-khung-soạn-thảo)
14. [Thêm nhanh](#14-thêm-nhanh)
15. [Xem trước Markdown và màu cú pháp](#15-xem-trước-markdown-và-màu-cú-pháp)
16. [Chủ đề, phông chữ và chữ CJK](#16-chủ-đề-phông-chữ-và-chữ-cjk)
17. [Lưu, bản chụp và bảng mã](#17-lưu-bản-chụp-và-bảng-mã)
18. [Tham khảo cài đặt](#18-tham-khảo-cài-đặt)
19. [Phím tắt](#19-phím-tắt)
20. [Các tệp HyperEdit ghi](#20-các-tệp-hyperedit-ghi)
21. [Khắc phục sự cố](#21-khắc-phục-sự-cố)
22. [Hạn chế đã biết](#22-hạn-chế-đã-biết)
23. [Nhận trợ giúp](#23-nhận-trợ-giúp)

## 1. Cài đặt và cập nhật

**Yêu cầu:** macOS 15 (Sequoia) trở lên. Ứng dụng là universal binary (Apple Silicon và Intel), đã được ký và công chứng, nên Gatekeeper mở mà không cảnh báo.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Về sau, cập nhật bằng `brew upgrade --cask hyperedit`. Homebrew 7 có thể yêu cầu bạn tin cậy tap trước: `brew trust Hyeongcheol-An/tap`.

**DMG:** tải `HyperEdit-x.y.z.dmg` từ [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), mở ra và kéo `HyperEdit.app` vào `Applications`. Để xác minh bản tải về, đặt `SHA256SUMS` cạnh tệp DMG và chạy `shasum -a 256 -c SHA256SUMS`.

HyperEdit không có mã mạng và không có telemetry: nó không bao giờ tự kết nối về máy chủ, và việc cập nhật là do bạn làm, không phải do nó tự làm.

## 2. Khởi chạy lần đầu

HyperEdit mở `~/Documents/HyperEdit/notes.md`. Nếu tệp đó chưa tồn tại, nó được tạo với một đoạn chào mừng ngắn bằng ngôn ngữ của bạn — hãy xóa đoạn đó và bắt đầu viết. Ý tưởng là bạn giữ một tệp và cứ thêm vào, nhưng không có gì bắt buộc điều đó:

- **⌘N** tạo một tệp văn bản trống mới (bạn chọn tên và thư mục).
- **⌘O** mở bất kỳ tệp văn bản nào khác. Tệp mở gần nhất được ghi nhớ cho lần khởi chạy sau.
- **Tệp › Mở tài liệu mặc định** đưa bạn về `notes.md`.
- Tệp nhị phân (ảnh, PDF, tệp nén…) không bao giờ được nạp vào trình soạn thảo; chúng mở bằng ứng dụng mặc định.

Vị trí con trỏ và vị trí cuộn được ghi nhớ theo từng tệp, nên mở lại một tệp 30.000 dòng sẽ đưa bạn về đúng chỗ đã dừng. **⌃⌘E** nhảy tới cuối tài liệu — nơi bạn thường muốn đến trong một tệp ghi chú.

## 3. Ngôn ngữ giao diện

Giao diện có sẵn mười một ngôn ngữ: English (tiếng Anh), 한국어 (tiếng Hàn), 简体中文 (tiếng Trung giản thể), 日本語 (tiếng Nhật), Tiếng Việt, हिन्दी (tiếng Hindi), Deutsch (tiếng Đức), Français (tiếng Pháp), Español (tiếng Tây Ban Nha), Português (tiếng Bồ Đào Nha, chính tả Brazil) và العربية (tiếng Ả Rập). Văn bản tiếng Ả Rập được viết từ phải sang trái, nhưng bố cục cửa sổ — ribbon, thanh bên, các bảng và trình soạn thảo — vẫn giữ từ trái sang phải như hầu hết các trình soạn thảo mã; văn bản bạn gõ theo hướng riêng của nó.

Mặc định HyperEdit theo ngôn ngữ hệ thống. Để chọn ngôn ngữ khác:

1. Mở **Cài đặt (⌘,)** và xem mục **Ngôn ngữ** ở trên cùng.
2. Chọn một ngôn ngữ trong menu **Ngôn ngữ giao diện**. Mỗi ngôn ngữ được liệt kê bằng chính chữ viết của nó, nên bạn có thể tìm thấy ngôn ngữ của mình ngay cả khi ngôn ngữ hiện tại xa lạ. **Mặc định hệ thống** cho biết cài đặt hệ thống sẽ dùng ngôn ngữ nào.
3. Nhấp **Khởi chạy lại ngay**. Tài liệu được lưu trước, rồi HyperEdit thoát và mở lại bằng ngôn ngữ mới. (Bạn cũng có thể tiếp tục làm việc và khởi chạy lại sau; lựa chọn đã được lưu.)

Lựa chọn này được lưu ở cùng chỗ với **Cài đặt hệ thống › Cài đặt chung › Ngôn ngữ & Vùng › Ứng dụng**, nên hai bên luôn khớp nhau. **Trợ giúp › Hướng dẫn sử dụng** và nút **Mở hướng dẫn sử dụng** trong Cài đặt mở hướng dẫn này bằng ngôn ngữ giao diện hiện tại.

Ngôn ngữ không có trong danh sách sẽ dùng tiếng Anh (ví dụ tiếng Trung phồn thể). Nội dung tài liệu, tên tệp và ngày bạn chèn không bị ảnh hưởng bởi ngôn ngữ giao diện — thứ trong dấu thời gian theo ngôn ngữ vùng của hệ thống.

## 4. Cửa sổ

Bố cục theo kiểu trình soạn thảo ribbon cổ điển, với thanh tiêu đề ẩn.

- **Các tab ribbon** — **Trang đầu** (Bảng nhớ tạm, Tìm, Chèn, Chế độ, Tệp), **Chỉnh sửa** (Dòng, Chữ hoa/thường, Sắp xếp, Khoảng trắng, Cột & Đa con trỏ, Công cụ, Macro), **Bố cục** (Chủ đề, Bảng, Thu gọn, Markdown, Cỡ chữ), **Nâng cao** (Cài đặt, thư mục bản chụp, tải lại, tài liệu mặc định), **Cửa sổ** (toàn màn hình, các bảng). Khi cửa sổ hẹp, các nhóm thu thành biểu tượng từ bên phải; chú giải công cụ của biểu tượng hiện nhãn.
- **Thanh tab tài liệu** — tên tệp hiện tại với nút Mới (⌘N) và Mở (⌘O), cùng các nút nhanh Lưu / Hoàn tác / Làm lại.
- **Thanh bên (⌘1)** — **Tệp** (thư mục của tệp hiện tại; nhấp một lần để mở tệp), **Dàn ý (⌘3)** (tiêu đề, dòng `[Tiêu đề]` và mục đánh số, có ô lọc; mục hiện tại được tô sáng), **Dòng thời gian (⌘4)** (tiêu đề dấu thời gian nhóm theo tháng, mới nhất trước).
- **Bảng dưới (⌘2)** — **Kết quả tìm kiếm**, **Dấu trang** và **Đầu ra**, nhật ký những gì ứng dụng đã làm (lưu, thay thế, lỗi).
- **Thanh trạng thái** — dòng và cột (cùng độ dài vùng chọn; di chuột để xem vị trí ký tự), kết thúc dòng (UNIX / DOS / MAC), bảng mã tệp, **COL** khi chế độ cột đang bật, số con trỏ, số dòng · kích thước tệp, thông báo trạng thái mới nhất, ngôn ngữ cú pháp (mờ khi màu cú pháp tắt), menu chủ đề (đánh dấu "· Hệ thống" khi theo giao diện hệ thống) và tỷ lệ thu phóng. Hầu hết các mục đều nhấp được.

## 5. Chỉnh sửa cơ bản

- Gõ bình thường vẫn nhanh trong các tệp nhiều megabyte; chỉ phần nhìn thấy của tài liệu được dàn trang.
- **Ngắt dòng** ⌥Z · **Số dòng** ⌥⌘L · **Thu phóng** ⌘= / ⌘- / ⌘0 (cũng có trong tab Bố cục).
- **Đi tới dòng** ⌘L · **Cuối tài liệu** ⌃⌘E.
- **Chèn ngày/giờ** F7 chèn tiêu đề dấu thời gian như `## 2026-10-31 (Th 6) 14:05`. Thứ theo ngôn ngữ vùng của hệ thống. Những dòng như vậy cung cấp dữ liệu cho Dòng thời gian.
- Dòng hiện tại được tô sáng và lề hiện số dòng bằng màu chữ.
- Hoàn tác và làm lại không giới hạn trong một phiên, và mỗi công cụ dưới đây là một bước hoàn tác duy nhất.

## 6. Tìm và thay thế

- **Tìm (⌘F)** mở thanh Tìm. Gõ truy vấn và nhấn Enter: mọi kết quả được liệt kê trong bảng dưới kèm số dòng, và các kết quả được tô sáng trong trình soạn thảo khi danh sách đang mở. Các nút bật/tắt: biểu thức chính quy `.*`, phân biệt hoa thường `Aa`, cả từ `W`. **F3 / ⇧F3** chuyển tới kết quả kế tiếp / trước. Danh sách tự làm mới khoảng một giây sau khi bạn chỉnh sửa.
- **Thay thế (⌘R)** thêm ô thay thế: thay kết quả hiện tại rồi chuyển tiếp, hoặc **Thay thế tất cả**. Khi bật biểu thức chính quy, các mẫu như `$1` chèn nhóm bắt. Thay thế tất cả là một bước hoàn tác, kể cả với hàng nghìn kết quả.
- **Tìm trong tệp (⇧⌘F)** tìm trong một thư mục (gồm cả thư mục con). Chọn thư mục, tùy chọn giới hạn bằng mẫu lọc như `*.md;*.txt`, và nhấp một kết quả để mở tệp đó tại đúng dòng. Tệp ẩn, gói, tệp nhị phân và tệp trên 20 MB bị bỏ qua.
- **Chọn tất cả kết quả (⌥⌘A)** biến mọi kết quả thành một con trỏ — xem phần đa con trỏ bên dưới.

## 7. Dấu trang

**⌘F2** đánh dấu dòng hiện tại (hoặc gỡ dấu trang), **F2 / ⌥F2** nhảy tới dấu trang kế tiếp / trước, và tab **Dấu trang** của bảng dưới liệt kê tất cả; bạn có thể đặt tên cho dấu trang ở đó. Dấu trang đi theo dòng của nó khi bạn chỉnh sửa: chèn hoặc xóa dòng phía trên sẽ dời chúng, xóa dòng có dấu trang sẽ gỡ nó, và hoàn tác đưa chúng trở lại. Chúng được lưu theo từng tài liệu trong `~/Library/Application Support/HyperEdit/bookmarks/`, nên không có gì được ghi cạnh tệp của bạn.

## 8. Chế độ cột và đa con trỏ

- **Chế độ cột (⌥C)** — giữ ⌥ và kéo, hoặc dùng ⇧ với phím mũi tên, để chọn một hình chữ nhật. Gõ và xóa khi đó áp dụng cho mọi dòng của khối, dòng ngắn được đệm bằng khoảng trống ảo, và sao chép / dán hoạt động theo từng dòng. Thanh trạng thái hiện **COL**. ⌥C lần nữa để tắt.
- **Chèn số (⌥⌘N)** — điền vùng chọn cột (hoặc mọi con trỏ) bằng một dãy số: chọn giá trị đầu và bước nhảy; các số được đệm số 0 cho cùng độ rộng.
- **Đa con trỏ** — ⌘-nhấp thêm một con trỏ, **⌘D** thêm lần xuất hiện kế tiếp của văn bản đã chọn (hoặc từ tại con trỏ), **⌥⌘A** chọn mọi kết quả tìm kiếm. Gõ sẽ áp dụng cho mọi con trỏ; Esc trở về một con trỏ. Mỗi lần chỉnh sửa đa con trỏ là một bước hoàn tác.

## 9. Công cụ dòng và văn bản

Các công cụ này nằm trong tab ribbon **Chỉnh sửa** và trong menu **Dòng**. Chúng tác động lên các dòng đã chọn, hoặc dòng hiện tại khi không có gì được chọn.

| Nhóm | Công cụ |
|---|---|
| Dòng | Xóa dòng ⇧⌘K · Nhân bản dòng ⇧⌘D · Chuyển dòng lên / xuống ⌥↑ / ⌥↓ · Nối dòng ⇧⌘J · Đảo ngược dòng · Đánh số dòng |
| Chữ hoa/thường | Chữ hoa · Chữ thường · Viết hoa đầu từ · Đảo hoa/thường |
| Sắp xếp | Tăng dần · Giảm dần · Sắp xếp theo số (theo số ở đầu mỗi dòng) · Xóa dòng trùng lặp |
| Khoảng trắng | Xén khoảng trắng cuối dòng · Xén khoảng trắng hai đầu dòng · Xóa dòng trống · Tab → Dấu cách · Dấu cách → Tab |

- **Tính toán (⌃⌘=)** tính vùng chọn, hoặc dòng hiện tại (phần sau dấu `=` cuối cùng nếu có), và thêm ` ⇒ kết quả` vào cuối: `3+0.5+0.25` trở thành `3+0.5+0.25 ⇒ 3.75`. Chạy lại trên dòng đã sửa sẽ thay kết quả cũ. Hỗ trợ: `+ - * / % ^`, dấu ngoặc, số dạng `1,234` và `1_000`, `sqrt abs round floor ceil min max`, `pi` và `e`. Biểu thức không tính được sẽ được báo trong bảng Đầu ra và văn bản được giữ nguyên.
- **Căn chỉnh cột (⌃⌘T)** đệm các cột phân cách bằng tab (các dòng đã chọn, hoặc khối dòng có tab quanh con trỏ) để mỗi cột bắt đầu ở cùng một cột hiển thị; chữ Hàn, Trung và Nhật tính là hai ô. Nếu mọi dòng đều chứa `|`, khối được xử lý như bảng Markdown: các ô được đệm bên trong ` | `, các hàng `---` được vẽ lại và cột `--:` được căn phải.
- **Bật/tắt chú thích (⌘/)** thêm hoặc bỏ chú thích cho các dòng bằng ký hiệu của loại tệp: `//`, `#`, `--`… cho mã, `<!-- -->` cho Markdown và HTML, `/* */` cho CSS, `//` cho ghi chú thuần. Nếu mọi dòng không trống đều đã có chú thích thì tất cả được bỏ chú thích, ngược lại tất cả được thêm chú thích, với ký hiệu căn theo mức thụt lề nông nhất. Dòng trống bị bỏ qua.
- **Định dạng JSON (⌃⌘J) / Rút gọn JSON** định dạng đẹp (thụt lề 2 dấu cách) hoặc thu gọn vùng chọn, hoặc toàn bộ tài liệu khi không có gì được chọn. Thứ tự khóa và cách viết số được giữ nguyên, văn bản không phải ASCII không bị escape, và đầu vào có thể chứa chú thích và dấu phẩy cuối (JSONC). Khi có lỗi cú pháp, văn bản được giữ nguyên, bảng Đầu ra hiện `dòng:cột` và con trỏ nhảy tới đó.

## 10. Đoạn mẫu

Gõ một từ kích hoạt và nhấn **Tab** để mở rộng nó. Từ kích hoạt có sẵn: `todo`, `date`, `time`, `now`, `meeting`, `table`, `link`, `code`. **Chèn đoạn mẫu… (⇧⌘I)** liệt kê tất cả kèm ô lọc, và tab Trang đầu có nút Đoạn mẫu….

Thân đoạn mẫu có thể chứa biến — `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` — và các điểm dừng tab `$1` … `$9`, `${1:placeholder}` và `$0`. Sau khi mở rộng, Tab / ⇧Tab di chuyển giữa các điểm dừng (một số dùng hai lần trở thành đa con trỏ), và Esc hoặc một cú nhấp kết thúc phiên.

**Sửa đoạn mẫu…** (menu Chỉnh sửa hoặc tab Trang đầu) mở `~/Library/Application Support/HyperEdit/snippets.json` ngay trong HyperEdit. Mỗi mục có `trigger`, `name` và `body`; tệp được đọc lại sau khi bạn lưu, nên từ kích hoạt mới dùng được ngay.

## 11. Macro

Macro ghi lại những gì bạn gõ và phát lại ở nơi khác.

1. **Ghi macro (⇧⌘M)** bắt đầu ghi; thanh trạng thái hiện `● REC`. Thao tác gõ (với tiếng Hàn và các bộ gõ IME khác là các ký tự đã xác nhận), di chuyển con trỏ, xóa, xuống dòng, dán, các công cụ văn bản và Tìm tiếp (F3, kèm truy vấn) đều được ghi. Nhấp chuột, thay đổi vùng chọn và chỉnh sửa đa con trỏ thì không.
2. **⇧⌘M** lần nữa để dừng ghi.
3. **Phát macro (⌥⌘M)** phát lại tại con trỏ. **Phát macro nhiều lần…** lặp lại tới 10.000 lần và tự dừng khi bước Tìm không thấy gì hoặc một lượt không thay đổi gì — một công cụ tiện lợi kiểu "làm việc này với mọi dòng". Toàn bộ lượt chạy là một bước hoàn tác.

Bản ghi gần nhất chỉ nằm trong bộ nhớ cho đến khi bạn thoát, nên những gì nhạy cảm bạn gõ khi đang ghi không bao giờ đến đĩa. **Lưu macro vừa ghi dưới dạng…** thêm nó vào menu **Macro** lâu dài; các macro đã lưu nằm trong `~/Library/Application Support/HyperEdit/macros/macros.json`, tệp mà **Sửa tệp macro…** mở trong trình soạn thảo.

## 12. Thu gọn mã và dấu thanh cuộn

**Thu gọn (⌥⌘←) / Mở rộng (⌥⌘→)** ẩn hoặc hiện vùng tại con trỏ; **⌥⇧⌘← / ⌥⇧⌘→** thu gọn hoặc mở rộng tất cả. Một vùng là:

- các dòng thụt lề dưới dòng hiện tại (bỏ qua dòng trống),
- trong Markdown, mọi thứ dưới một tiêu đề `#` cho đến tiêu đề kế tiếp cùng cấp hoặc cao hơn (khối mã rào cũng thu gọn được),
- trong mã, một dòng kết thúc bằng `{`, `[` hoặc `(` cho đến dòng có dấu đóng tương ứng.

Nhấp chevron ở lề hoặc viên `⋯ N dòng` sau dòng đã thu gọn để bật/tắt bằng chuột. Di chuyển con trỏ vào dòng đã thu gọn (tìm, đi tới dòng, dấu trang, hoàn tác) sẽ mở rộng nó; ↑ / ↓ nhảy qua các vùng thu gọn. Các vùng thu gọn đi theo chỉnh sửa của bạn và tồn tại trong phiên.

**Dấu thanh cuộn** — một dải mỏng ở mép phải trình soạn thảo hiện kết quả tìm kiếm (màu nhấn), dấu trang (màu cảnh báo), dòng con trỏ và tiêu đề đã thu gọn ở vị trí tương đối trong tệp. Dải này ẩn khi toàn bộ tài liệu vừa màn hình. Tắt nó trong **Hiển thị › Dấu thanh cuộn** hoặc trong nhóm Thu gọn của tab Bố cục.

## 13. Chia đôi khung soạn thảo

**⌘\\** hiện cùng một tài liệu trong hai khung soạn thảo cạnh nhau; **Hiển thị › Chia đôi › Chia trên dưới** đặt chúng trên dưới, và tab Bố cục có các nút tương tự. Cả hai khung chỉnh sửa cùng một văn bản và dùng chung một lịch sử hoàn tác — gõ ở khung này, ⌘Z ở khung kia — nhưng cuộn độc lập, nên bạn có thể đọc một phần của tệp trong khi viết ở phần khác. Các lệnh, thanh trạng thái và xem trước Markdown theo khung bạn nhấp gần nhất; **⌥⌘\\** chuyển tiêu điểm sang khung kia. Thanh trạng thái hiện **SPLIT** khi đang chia đôi; ⌘\\ lần nữa để đóng.

## 14. Thêm nhanh

**Thêm nhanh (⇧⌘N)** mở một bảng nổi nhỏ để thêm ghi chú mà không rời việc đang làm. Gõ ghi chú, nhấn **⌘↩**, và nó được thêm vào cuối tài liệu — mặc định kèm tiêu đề dấu thời gian — lưu ngay và hoàn tác được trong một bước. Bảng sau đó ẩn đi và tiêu điểm trở về ứng dụng bạn đang dùng. **Esc** đóng bảng và giữ bản nháp cho lần sau.

Vì bảng này không kích hoạt HyperEdit, nó cũng hoạt động từ bất kỳ ứng dụng nào khác qua **phím tắt toàn cục**: mặc định là **⌃⌥N**. Trong Cài đặt, bạn có thể tắt nó hoặc chọn ⌃⌥Space, ⌃⇧Space hay ⌃⌥⌘N thay thế, và tắt tiêu đề dấu thời gian. Phím tắt dùng dịch vụ hot-key của hệ thống, nên không cần quyền Trợ năng. Nếu ứng dụng khác đã chiếm tổ hợp phím, bảng Đầu ra sẽ báo khi khởi chạy — hãy chọn tổ hợp khác.

## 15. Xem trước Markdown và màu cú pháp

- **Xem trước Markdown (⇧⌘P)** chia cửa sổ với một khung hiển thị tệp hiện tại đã kết xuất ở bên phải: tiêu đề, danh sách và danh sách việc cần làm, bảng, khối mã rào, trích dẫn, liên kết và hình ảnh, theo phong cách của chủ đề hiện tại. Nó theo vị trí cuộn của trình soạn thảo và kết xuất lại ngay sau khi bạn ngừng gõ. Liên kết mở trong trình duyệt của bạn; HTML thô trong tệp được hiện dưới dạng văn bản, không bao giờ được thực thi. Tệp trên 2 MB hiện thông báo thay vì xem trước. Thanh trạng thái hiện **MD** khi đang bật.
- **Màu cú pháp (⌃⌘H)** được chọn theo phần mở rộng tệp và hiện trên thanh trạng thái. Ghi chú và Markdown có bộ quy tắc nhẹ — URL, ngày và giờ, tiêu đề, dòng `[Tiêu đề]`, ký hiệu danh sách và ô việc `[ ]` / `[x]`, `#thẻ`, nhãn `key:`, `**đậm**`, `` `mã` `` và mũi tên `⇒ → ->` — và khoảng 20 ngôn ngữ lập trình có chú thích, chuỗi, số, từ khóa, tên hàm và tên kiểu. Màu chỉ được vẽ trên các dòng nhìn thấy, nên không bao giờ thay đổi tệp hay làm chậm việc gõ. Tô màu theo dòng: chú thích hoặc chuỗi trải nhiều dòng chỉ được tô ở dòng mở đầu.

## 16. Chủ đề, phông chữ và chữ CJK

**Chủ đề.** 22 bảng màu — 5 sáng, 17 tối — đi kèm ứng dụng. Mặc định nó theo giao diện hệ thống: **Hyper Light** ở chế độ sáng, **Hyper Dark** ở chế độ tối. Chọn một chủ đề từ tab Bố cục, menu chủ đề trên thanh trạng thái, **Hiển thị › Chủ đề** hoặc ⌥⌘] / ⌥⌘[ để cố định; **Theo giao diện hệ thống** nằm trong cùng các menu đó và trong Cài đặt. Các bảng màu này cũng có sẵn cho trình soạn thảo Zed (`hyperedit-themes.json` trong mỗi bản phát hành).

**Phông chữ.** HyperEdit dùng **Fira Code** khi đã cài và phông monospace của hệ thống khi chưa. Chữ Hàn được vẽ bằng một phông riêng — mặc định là **D2Coding**, khi đã cài — được co giãn sao cho một âm tiết Hangul rộng đúng bằng hai ô Latin, giúp các bảng căn bằng tab luôn thẳng. Chữ ghép, chiều cao dòng, cả hai họ phông và tỷ lệ Hangul đều nằm trong Cài đặt. Chữ Trung và Nhật dùng phông dự phòng của hệ thống và cũng tính là hai ô trong Căn chỉnh cột.

## 17. Lưu, bản chụp và bảng mã

- **Tự động lưu** chạy hai giây sau khi bạn ngừng gõ (⌘S lưu ngay). Khi thoát, đóng cửa sổ và khi chuyển tệp, tài liệu được lưu ngay lập tức, nên không mất gì trong khoảng hai giây đó. Mọi lần ghi đều là nguyên tử.
- **Bản chụp.** Trước lần lưu đầu tiên của mỗi phiên, một bản sao của tệp được lưu trong `~/Library/Application Support/HyperEdit/snapshots` (**Tệp › Mở thư mục bản chụp**). 20 bản mới nhất của mỗi tệp được giữ lại và bản nào cũ hơn 90 ngày sẽ bị xóa.
- **Thay đổi bên ngoài.** Nếu chương trình khác thay đổi tệp khi đang mở và bạn không có chỉnh sửa chưa lưu, HyperEdit tải lại tệp và giữ nguyên vị trí con trỏ. Nếu bạn có chỉnh sửa chưa lưu, phiên bản bên ngoài được chụp lại và một cảnh báo hiện ra; lưu khi đó sẽ ghi đè lên nó.
- **An toàn.** Bộ đệm trống không bao giờ được ghi đè lên tệp từng có nội dung. Nếu lưu thất bại khi bạn thoát, một bản sao khẩn cấp được ghi vào thư mục bản chụp và bạn được hỏi có vẫn thoát hay không.
- **Bảng mã.** Tệp được đọc dưới dạng UTF-8 trước, rồi EUC-KR (CP949), CP1252 và Latin-1, và được lưu bằng cùng bảng mã (BOM UTF-8 được giữ nguyên). Nếu bạn gõ một ký tự mà bảng mã gốc không lưu được, tệp được lưu dưới dạng UTF-8 và thanh trạng thái sẽ báo. Tệp không giải mã được bằng bất kỳ bảng mã nào trong số này sẽ không được mở, thay vì bị hỏng.
- **Kết thúc dòng** (UNIX / DOS / MAC) được phát hiện và giữ nguyên; Thêm nhanh và các công cụ văn bản dùng kiểu của chính tệp.

## 18. Tham khảo cài đặt

Mở Cài đặt bằng **⌘,** hoặc tab Nâng cao.

| Mục | Điều khiển gì |
|---|---|
| Ngôn ngữ | Ngôn ngữ giao diện (Mặc định hệ thống hoặc một trong mười một ngôn ngữ), **Khởi chạy lại ngay**, **Mở hướng dẫn sử dụng** |
| Phông chữ | Họ phông Latin, cỡ chữ, chữ ghép, chiều cao dòng |
| Hangul | Họ phông Hangul, sửa độ rộng 2:1, tỷ lệ Hangul; cho biết phông đã cài hay chưa |
| Chủ đề | Theo giao diện hệ thống, bộ chọn chủ đề |
| Tệp | Tệp hiện tại, tài liệu mặc định và thư mục bản chụp, kèm nút để mở |
| Thêm nhanh | Phím tắt toàn cục (Tắt / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N), bật/tắt tiêu đề dấu thời gian |

Trạng thái hiện/ẩn các bảng, ngắt dòng, số dòng, màu cú pháp, dấu thanh cuộn, chia đôi khung và tab ribbon được ghi nhớ tự động.

## 19. Phím tắt

| Phím tắt | Thao tác | Phím tắt | Thao tác |
|---|---|---|---|
| ⌘N | Tài liệu mới | ⌘O | Mở |
| ⌘S | Lưu | ⌘F | Tìm |
| ⌘R | Thay thế | ⇧⌘F | Tìm trong tệp |
| F3 / ⇧F3 | Kết quả kế tiếp / trước | ⌘L | Đi tới dòng |
| ⌃⌘E | Cuối tài liệu | ⌥C | Chế độ cột |
| ⌘D | Thêm lần xuất hiện kế tiếp | ⌥⌘A | Chọn tất cả kết quả |
| ⌥⌘N | Chèn số | F7 | Chèn dấu thời gian |
| ⌘F2 | Bật/tắt dấu trang | F2 / ⌥F2 | Dấu trang kế tiếp / trước |
| ⇧⌘K | Xóa dòng | ⇧⌘D | Nhân bản dòng |
| ⌥↑ / ⌥↓ | Chuyển dòng lên / xuống | ⇧⌘J | Nối dòng |
| ⌃⌘= | Tính toán | ⌃⌘T | Căn chỉnh cột |
| ⌘/ | Bật/tắt chú thích | ⌃⌘J | Định dạng JSON |
| ⇧⌘I | Chèn đoạn mẫu | Tab | Mở rộng đoạn mẫu / điểm dừng kế tiếp |
| ⇧⌘M | Ghi / dừng macro | ⌥⌘M | Phát macro |
| ⌥⌘← / ⌥⌘→ | Thu gọn / mở rộng | ⌥⇧⌘← / ⌥⇧⌘→ | Thu gọn tất cả / mở rộng tất cả |
| ⌘\\ | Chia đôi khung | ⌥⌘\\ | Chuyển sang khung kia |
| ⇧⌘N | Thêm nhanh | ⌃⌥N | Thêm nhanh từ bất kỳ ứng dụng nào (tùy chỉnh được) |
| ⌘1 | Thanh bên | ⌘2 | Bảng dưới |
| ⌘3 | Dàn ý | ⌘4 | Dòng thời gian |
| ⌥⌘L | Số dòng | ⌥Z | Ngắt dòng |
| ⇧⌘P | Xem trước Markdown | ⌃⌘H | Màu cú pháp |
| ⌥⌘] / ⌥⌘[ | Chủ đề kế tiếp / trước | ⌘= / ⌘- / ⌘0 | Phóng to / thu nhỏ / đặt lại |
| ⌘, | Cài đặt | ⌘Q | Thoát (lưu trước) |

## 20. Các tệp HyperEdit ghi

HyperEdit chỉ đụng đến các tệp bạn mở và dữ liệu của chính nó:

| Đường dẫn | Nội dung |
|---|---|
| `~/Documents/HyperEdit/notes.md` | Tài liệu mặc định (tạo khi khởi chạy lần đầu nếu chưa có) |
| `~/Library/Application Support/HyperEdit/snapshots/` | Bản chụp trước khi lưu và bản sao khẩn cấp |
| `~/Library/Application Support/HyperEdit/bookmarks/` | Một tệp JSON cho mỗi tài liệu có dấu trang |
| `~/Library/Application Support/HyperEdit/snippets.json` | Đoạn mẫu của bạn |
| `~/Library/Application Support/HyperEdit/macros/macros.json` | Macro đã lưu |
| `~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist` | Tùy chọn, bao gồm ngôn ngữ giao diện |

Không có gì được ghi cạnh tài liệu của bạn, và không có gì rời khỏi máy Mac của bạn.

## 21. Khắc phục sự cố

- **Ngôn ngữ không thay đổi.** Ngôn ngữ mới áp dụng sau khi khởi chạy lại — dùng **Khởi chạy lại ngay** trong Cài đặt hoặc thoát rồi mở lại. Nếu ngôn ngữ hệ thống là ngôn ngữ HyperEdit không có, nó hiện tiếng Anh; hãy chọn ngôn ngữ rõ ràng trong Cài đặt.
- **Một tệp không mở được.** Tệp nhị phân cố ý mở bằng ứng dụng mặc định. Tệp văn bản dùng bảng mã khác UTF-8, EUC-KR, CP1252 hoặc Latin-1 bị từ chối thay vì bị hỏng; hãy chuyển đổi bằng công cụ khác trước.
- **Phím tắt Thêm nhanh toàn cục không làm gì cả.** Ứng dụng khác có thể đã chiếm tổ hợp phím, hoặc ⌃Space / ⌃⌥Space có thể đã dùng cho chuyển nguồn nhập trong Cài đặt hệ thống › Bàn phím. Hãy chọn ⌃⌥N hoặc ⌃⌥⌘N trong Cài đặt. Bảng Đầu ra báo kết quả đăng ký khi khởi chạy.
- **Chữ Hàn trông quá rộng hoặc quá hẹp trong bảng.** Cài D2Coding, hoặc điều chỉnh tỷ lệ Hangul trong Cài đặt; sửa độ rộng 2:1 cần một phông Hangul monospace.
- **Tôi lỡ lưu nhầm.** Mở thư mục bản chụp (**Tệp › Mở thư mục bản chụp**): bản sao chụp trước lần lưu đầu tiên của phiên nằm ở đó, cùng các bản sao được tạo khi phát hiện thay đổi bên ngoài.
- **Ribbon chỉ hiện biểu tượng.** Cửa sổ quá hẹp cho tab đó; hãy mở rộng cửa sổ hoặc di chuột lên biểu tượng để xem nhãn.

## 22. Hạn chế đã biết

- Màu cú pháp theo dòng và không có ngữ pháp do người dùng định nghĩa. Xem trước Markdown là khung xem, không phải trình soạn thảo.
- Macro chỉ ghi thao tác chỉnh sửa bằng bàn phím (không có bước chuột, vùng chọn hay đa con trỏ). Tính toán và Căn chỉnh cột chỉ xử lý số học đơn giản và bảng tab / ống đứng.
- Đoạn mẫu và macro được chỉnh sửa dưới dạng tệp JSON; không có trình soạn thảo đồ họa cho chúng.
- Vùng thu gọn tồn tại trong phiên và không được lưu theo tệp; kéo chuột qua dòng đã thu gọn vẫn chọn văn bản bị ẩn.
- Tài liệu chỉ có một dòng dài từ một megabyte trở lên mở và di chuyển chậm; Rút gọn JSON cảnh báo trước khi tạo ra dòng như vậy.
- Chỉ tệp cục bộ; chưa có đồng bộ đám mây và chưa có ứng dụng iOS.
- Ngôn ngữ ngoài mười một ngôn ngữ đã liệt kê sẽ dùng tiếng Anh.

## 23. Nhận trợ giúp

- Báo lỗi và ý tưởng: [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) và [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions).
- Vấn đề bảo mật: xem [SECURITY.md](../../SECURITY.md) để báo cáo riêng tư.
- Bản dịch: các chuỗi giao diện nằm trong `l10n/ui.<language>.json` của kho mã nguồn và hướng dẫn này trong `docs/guide/`; hoan nghênh sửa lỗi qua pull request — xem [CONTRIBUTING.md](../../CONTRIBUTING.md).

HyperEdit là phần mềm tự do theo Giấy phép MIT. Bố cục của nó lấy cảm hứng từ ribbon UltraEdit cổ điển; UltraEdit là nhãn hiệu của IDM Computer Solutions, Inc., và HyperEdit không liên kết với IDM.
