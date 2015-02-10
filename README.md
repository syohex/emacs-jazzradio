# jazzradio.el

This is Emacs port of [jazzradio.vim](https://github.com/supermomonga/jazzradio.vim)


## Screenshot

![jazzradio](image/jazzradio.png)

## Requirements

- Emacs 24.1 or higher
- mplayer
- curl

## Basic Usage

#### `jazzradio`

Show channel list.

#### `jazzradio-pop-to-buffer`

Pop up buffer version

## Key Bindings

| Key        | Command            |
|:-----------|:-------------------|
| `RET`      | Play channel       |
| `U`        | Stop channel       |
| `SPC`      | Toggle pause/play  |
| `9`        | Decrease volume    |
| `0`        | Increase volume    |


## Customize variable

#### `jazzradio-channel-url`

#### `jazzradio-playlist-base-url`

#### Example

```lisp
(custom-set-variables
 '(jazzradio-channel-url "http://ephemeron:dayeiph0ne%40pp@api.audioaddict.com/v1/di/mobile/batch_update?stream_set_key=")
 '(jazzradio-playlist-base-url "http://listen.di.fm/webplayer/"))
```
