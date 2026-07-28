# Integrating VaultX with Xcode on macOS

This project provides the foundational SwiftUI source files for the VaultX locking mechanism.

> [!NOTE]
> `VaultX.xcodeproj` now exists in this repository. However, it has not yet been built or tested with Xcode natively since it was generated in a Windows environment.

## 1. Open the Xcode Project
1. Transfer this entire `VaultX1` directory to your macOS machine.
2. Open `VaultX.xcodeproj` in Xcode.
3. The project is already configured with the correct targets, files, Face ID plist entries, and signing style.

## 4. Run the Application
1. Select a Simulator (e.g., iPhone 15 Pro) or a connected iOS device.
2. Press **Cmd + R** to build and run.
3. The app will launch into the `VaultXApp` entry point and present the setup or lock screen based on your keychain state.

## 5. Testing Face ID in Simulator
1. While the app is running in the Simulator, go to the Simulator menu bar.
2. Select **Features > Face ID > Enrolled** to simulate a device with Face ID set up.
3. When the app prompts for Face ID, select **Features > Face ID > Matching Face** (or Non-Matching Face) to test the authentication flows.

## 6. Fresh-Install and Keychain Persistence
- iOS Keychain items persist even after deleting an app from the Simulator or a physical device.
- VaultX relies on an `AppInstallationService` that detects true "fresh installs" by checking a `UserDefaults` marker (which *does* get deleted when the app is removed).
- Upon detecting a fresh install, VaultX automatically deletes the stale `vault-passcode` Keychain item and safely prepares the environment for a new passcode.

## 7. How to Run Unit Tests
1. Select the Test scheme or press `Cmd + U`.
2. Xcode will compile the `VaultXTests` target and run the included tests (`PasscodeValidationTests` and `AppLockStateTests`).
3. Note that fresh installation cases specifically assert that only VaultX-scoped mock items are deleted, preserving unrelated keys.

## 8. Note on Windows Environment
> [!CAUTION]
> The source files provided were generated on Windows. 
> - Compilation (`swiftc` native framework linking) was not executed. 
> - Apple framework type checking (`LocalAuthentication`, `CryptoKit`) was not validated by the Xcode build system.
> - Please report any compile-time errors encountered during your first Xcode build on macOS.
