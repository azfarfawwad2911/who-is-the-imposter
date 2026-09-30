# Kaun Imposter? — iPhone app source

Native SwiftUI app for iOS 16 or later. It has offline pass-the-phone play and online room play with the same Firebase Realtime Database project and data format as the Android APK. Classic, Double Trouble, Chaos, Blitz, 3–10 players, categories, private hold-to-reveal cards, timer, sounds, and result screens are implemented. Same app icon and word list as Android.

## Install on an iPhone

Open `KaunImposter.xcodeproj` in Xcode 15 or later on a Mac. Select target `KaunImposter`, choose your Apple development Team in Signing & Capabilities, select your connected iPhone, and press Run. Xcode handles development provisioning. The bundle identifier is `com.kaunimposter.ios`; change it in Signing if your Apple team needs a different identifier. The app is configured with the Firebase API key and Singapore Realtime Database URL supplied for this project. Firebase Anonymous Authentication must remain enabled and the supplied database rules must be published.

This environment cannot run Xcode, compile an iOS binary, or sign an IPA. Android was built separately; iOS source and project structure were checked here, but the iPhone build and a mixed Android/iPhone room still need device testing.
