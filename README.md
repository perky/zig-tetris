# Tetris 

A simple tetris clone written in
[zig programming language](https://github.com/andrewrk/zig).

## Multi-Threaded Fork.
This fork seperates rendering and logic into two seperate threads. The tetris logic is done in simulationLoop and the 
rendering in renderLoop.

This fork also adds automatic input recording. It records all keyboard input and then when you quit the application,
saves it to a file. You can then replay those inputs by launching the application with the recording file as an argument.

![](http://i.imgur.com/umuNndz.png)

## Controls

 * Left/Right/Down Arrow - Move piece left/right/down.
 * Up Arrow - Rotate piece clockwise.
 * Shift - Rotate piece counter clockwise.
 * Space - Drop piece immediately.
 * Left Ctrl - Hold piece.
 * R - Start new game.
 * P - Pause and unpause game.
 * Escape - Quit.
 
 **NEW**
 * L - Playback current recording.
 * K - Pause playback and continue playing from current state.
 * J - Restart and begin a new recording.

## Dependencies

 * [Zig compiler](https://github.com/andrewrk/zig) - use the debug build.
 * [libepoxy](https://github.com/anholt/libepoxy)

## Building and Running

```
zig build play
```

## Building on windows using vcpkg

* Install vcpkg https://github.com/microsoft/vcpkg
* Install dependencies using `x64-windows` triplet
* Use the flags `-Dwindows -Dvcpkg` when building the project

