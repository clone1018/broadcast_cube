# BroadcastCube

A copy of [broadcast-box](https://github.com/Glimesh/broadcast-box) but using the new [ex_webrtc](https://github.com/elixir-webrtc/ex_webrtc) library and Elixir!

Proof of concept.

## Running

```shell
mix deps.get
mix run --no-halt
```

## Early Benchmarking
It will be interesting to see how well a language that runs on the BEAM is able to handle a good amount of RTP packets. 
```
Stream Source: 
    Video: H264, 60fps, 1080p, 8000Kbps 
    Audio: OPUS, 48kHz, 2 Channels, 160bps

$ _build/dev/rel/broadcast_cube/bin/broadcast_cube start

HTTP Server Started, 0 Streamers, 0 Viewers: 0% CPU 102MB 
HTTP Server Started, 1 Streamers, 0 Viewers: 5.5% CPU 107MB
HTTP Server Started, 1 Streamers, 1 Viewers: 11.3% CPU 111MB
HTTP Server Started, 1 Streamers, 2 Viewers: 17.2% CPU 116MB
```