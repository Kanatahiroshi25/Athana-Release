Checks Athana's FLAC decoder (android/app/src/main/java/com/athana/lossless/AthanaFlac.java) against ffmpeg.
Needs: Java (javac), Python 3 with numpy, and ffmpeg on the PATH.

  python gen.py                      makes test FLAC files and ffmpeg's own decode of each (folder t)
  javac -d cls ..\..\android\app\src\main\java\com\athana\lossless\AthanaFlac.java Check.java
  java -cp cls Check t\s16_44k_lvl8.flac t\s16_44k_lvl8.raw     one file; OK means every byte is identical

Last run: 25 of 25 files identical (16 and 24 bit, 1 to 8 channels, 8 to 192 kHz).
