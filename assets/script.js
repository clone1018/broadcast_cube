let endpoint = "http://localhost:8829/api/whep/foobar";
let videoEl = document.getElementById("video1");

const log = msg => {
    document.getElementById("log").innerHTML += msg + "<br>";
}

log("Starting WebRTC connection");

async function setupStreamFromEndpoint(endpoint, videoEl) {
    let pc = new RTCPeerConnection({
        // iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] 
    });
    pc.addTransceiver('video', { direction: 'recvonly' });
    pc.addTransceiver('audio', { direction: 'recvonly' });
 
    pc.ontrack = event => {
        console.log("Got track", event)
        videoEl.srcObject = event.streams[0];
    }

    pc.oniceconnectionstatechange = e => {
        if (pc.iceGatheringState === "complete") {

            log(`pc.iceGatheringState === "complete"`);
        }
        log("oniceconnectionstatechange: " + pc.iceConnectionState);
    }
    pc.onicecandidate = ({candidate: candidate, url: url}) => {
        console.log("Got Ice Candidate", candidate, url);
    }
    let offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    document.getElementById("offer").innerText = offer.sdp;

    const resp = await fetch(endpoint, {
        method: 'POST',
        cache: 'no-cache',
        headers: {
            'Accept': 'application/sdp',
            'Content-Type': 'application/sdp'
        },
        body: offer.sdp
    });
    if (resp.status !== 201) {
        console.log('failed to negotiate')
        return;
    }

    let body = await resp.text();
    document.getElementById("answer").innerText = body;

    await pc.setRemoteDescription(new RTCSessionDescription({
        type: "answer",
        sdp: body
    }));

    log("WebRTC probably connected")
}


setupStreamFromEndpoint(endpoint, videoEl);