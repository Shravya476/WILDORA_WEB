WILDORA VOICE SEARCH ACCESSIBILITY UPDATE

- Manual Search now has a microphone button.
- User can speak a place name instead of typing it.
- Recognized speech is placed into the existing place search field.
- When speech recognition reaches a final result, WILDORA automatically searches the place and runs the existing time-based risk prediction.
- Existing MEDIUM interrupted horn and HIGH alarm behavior is preserved.
- Microphone permission is requested by the browser/device as needed.
- Android RECORD_AUDIO permission has been added.
- Screen-reader Semantics labels were added to the voice search controls.

BUILD NOTE:
Run `flutter pub get` before building so speech_to_text is resolved into pubspec.lock.
On the web, microphone access requires HTTPS (or localhost) and a browser that supports speech recognition, such as Chrome/Edge in supported environments.
