# Apple Health Flutter Test

Flutter app mot man hinh de test doc du lieu tu Apple Health/HealthKit.

## Chay thu tren iPhone

```bash
flutter pub get
flutter run
```

Neu Xcode bao loi signing, mo `ios/Runner.xcworkspace`, chon Apple Developer Team va doi bundle id trong Runner target sang bundle id rieng cua ban.

## Ghi chu

- App dung package `health` de xin quyen READ va doc cac `HealthDataType` iOS duoc ho tro.
- HealthKit chi co y nghia khi chay tren iPhone/iPad that, khong phai Android.
- iOS deployment target dang la `14.0` vi package `health` yeu cau muc nay.
