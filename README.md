# M.A.P Mastering Audio Pro (Flutter + FFmpeg)

## Chạy trên máy
```
flutter create --org com.map --project-name map_mastering --platforms=android .
# giữ nguyên lib/ và pubspec.yaml của dự án này (ghi đè nếu được hỏi)
```
Mở `android/app/build.gradle(.kts)` và đặt `minSdk = 24` (thay `flutter.minSdkVersion`). Sau đó:
```
flutter pub get
flutter run            # hoặc: flutter build apk --release --no-shrink --target-platform android-arm64
```
## Build APK bằng GitHub (không cần cài Flutter)
Upload toàn bộ thư mục (kèm `.github`) lên một repo GitHub → tab Actions → "Build Flutter APK" → tải artifact.

## Luồng sử dụng
Mở file → (Auto tự đặt thông số) → chỉnh núm → "Render & nghe thử" (FFmpeg render WAV 24-bit, phát đúng bản sẽ xuất) → "Bản gốc" để so sánh → "Lưu WAV 24-bit".

## Chuỗi filter FFmpeg
volume(input) → highshelf 12 kHz → equalizer 1 kHz (Q 0.8) → acompressor 3:1, attack 10 ms, release 250 ms + makeup → volume(output) → alimiter 0.891 (−1 dBFS) → `-c:a pcm_s24le`.
