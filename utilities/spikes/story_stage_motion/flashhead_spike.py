"""
Story Stage motion spike: one generated talking-head clip per spoken line.

Sends a character portrait and one line of synthesised speech through the Synesyn
hub to a ComfyUI running the SoulX-FlashHead node (usually on another machine),
then measures how long the clip took against how long the line lasts, and makes
the files needed to judge it by eye: an .ogv Godot can play, a contact sheet of
frames, and the same frames cut out with the portrait's own alpha mask.

	python flashhead_spike.py --check
	python flashhead_spike.py --runs 3
	python flashhead_spike.py --portrait path/to/idle/0.png --audio line.mp3 --model pro

The ComfyUI address is taken from --comfy-url, else render.comfy_url in the
client config, else the most recent render request the hub stored. The hub
address comes from hub.base_url in the same config. Needs Python 3.10+, Pillow,
and ffmpeg / ffprobe on PATH (or --ffmpeg).

See README.md in this folder for the rubric and the decision thresholds.
"""

from __future__ import annotations

import argparse
import base64
import copy
import io
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlparse
from urllib.request import Request, urlopen

from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SYNESYN_DOCS = Path.home() / "Documents" / "Synesyn"
CLIENT_CONFIG = Path(os.environ.get("SYNESYN_CLIENT_CONFIG") or SYNESYN_DOCS / "synesyn" / "config" / "synesyn_client.json")
DEFAULT_PORTRAIT = (
	REPO / "synesyn_client" / "ScenSyn" / "story_stage" / "sprites" / "cultural_narratives"
	/ "ireti_okan_awaiting_an_awakening" / "didi" / "idle" / "0.png"
)
WORKFLOW_TEMPLATE = HERE / "flashhead_line_clip.api.json"
FLASHHEAD_NODES = ("RunningHub SoulX-FlashHead Loader", "RunningHub SoulX-FlashHead Sampler")
NODE_SAMPLER, NODE_AUDIO, NODE_IMAGE, NODE_SAVE, NODE_LOADER = "2", "3", "4", "5", "6"


# --- configuration -----------------------------------------------------------

def load_client_config() -> dict[str, Any]:
	try:
		return json.loads(CLIENT_CONFIG.read_text(encoding="utf-8"))
	except (OSError, ValueError):
		return {}


def comfy_url_from_render_requests() -> str:
	found = sorted(
		SYNESYN_DOCS.glob("Workspaces/*/artifacts/json/render_request/*.json"),
		key=lambda p: p.stat().st_mtime,
		reverse=True,
	)
	for path in found[:25]:
		try:
			routing = json.loads(path.read_text(encoding="utf-8")).get("routing") or {}
		except (OSError, ValueError, AttributeError):
			continue
		url = str(routing.get("comfy_base_url") or "").strip()
		if url:
			return url
	return ""


def resolve_urls(args: argparse.Namespace, cfg: dict[str, Any]) -> tuple[str, str, str]:
	"""Returns (comfy_url, where_it_came_from, hub_url)."""
	render = cfg.get("render") if isinstance(cfg.get("render"), dict) else {}
	hub = cfg.get("hub") if isinstance(cfg.get("hub"), dict) else {}
	hub_url = (args.hub_url or str(hub.get("base_url") or "") or "http://127.0.0.1:17777").rstrip("/")
	if args.comfy_url:
		return args.comfy_url.rstrip("/"), "--comfy-url", hub_url
	if str(render.get("comfy_url") or "").strip():
		return str(render["comfy_url"]).strip().rstrip("/"), "render.comfy_url", hub_url
	history = render.get("comfy_url_history") if isinstance(render.get("comfy_url_history"), list) else []
	if history and str(history[0]).strip():
		return str(history[0]).strip().rstrip("/"), "render.comfy_url_history[0]", hub_url
	url = comfy_url_from_render_requests()
	if url:
		return url.rstrip("/"), "latest stored render request", hub_url
	return "", "", hub_url


# --- http --------------------------------------------------------------------

class Http:
	def __init__(self, token: str = "") -> None:
		self.token = token

	def call(self, method: str, url: str, body: Any = None, timeout: float = 60.0) -> dict[str, Any]:
		headers = {"Accept": "application/json"}
		data = None
		if body is not None:
			data = json.dumps(body).encode("utf-8")
			headers["Content-Type"] = "application/json"
		if self.token:
			headers["Authorization"] = f"Bearer {self.token}"
		req = Request(url, data=data, headers=headers, method=method)
		try:
			with urlopen(req, timeout=timeout) as resp:
				raw = resp.read().decode("utf-8")
		except HTTPError as e:
			raise RuntimeError(f"{method} {url} -> HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:400]}") from e
		obj = json.loads(raw) if raw else {}
		return obj if isinstance(obj, dict) else {"value": obj}


# --- media -------------------------------------------------------------------

def run(cmd: list[str]) -> str:
	res = subprocess.run(cmd, capture_output=True, text=True)
	if res.returncode != 0:
		raise RuntimeError(f"{Path(cmd[0]).name} failed: {res.stderr.strip()[-600:]}")
	return res.stdout


def probe(ffprobe: str, path: Path) -> dict[str, Any]:
	out = run([ffprobe, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)])
	info = json.loads(out)
	video = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), {})
	fps = 0.0
	if "/" in str(video.get("avg_frame_rate") or ""):
		num, den = str(video["avg_frame_rate"]).split("/")
		fps = float(num) / float(den) if float(den) else 0.0
	return {
		"duration_sec": float(info.get("format", {}).get("duration") or 0.0),
		"width": int(video.get("width") or 0),
		"height": int(video.get("height") or 0),
		"fps": round(fps, 3),
		"codec": video.get("codec_name", ""),
	}


def parse_crop(text: str) -> tuple[int, int, int, int] | None:
	if not text:
		return None
	x, y, w, h = (int(v) for v in text.split(","))
	return x, y, x + w, y + h


def prepare_portrait(src: Path, size: int, crop: tuple[int, int, int, int] | None, bg: str) -> tuple[Image.Image, Image.Image]:
	"""
	Square head-and-shoulders crop of an RGBA sprite, flattened onto a flat colour
	(FlashHead takes RGB). Returns (rgb_portrait, alpha_mask) at the same framing,
	so the mask can later be laid over generated frames.
	"""
	img = Image.open(src).convert("RGBA")
	alpha = img.getchannel("A")
	if crop is None:
		bbox = alpha.point(lambda a: 255 if a > 16 else 0).getbbox() or (0, 0, img.width, img.height)
		left, top, right, _bottom = bbox
		side = right - left
		pad = int(side * 0.08)
		crop = (left - pad, top - pad, right + pad, top - pad + side + 2 * pad)
	box = crop
	canvas = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
	canvas.paste(img.crop(box), (0, 0))
	canvas = canvas.resize((size, size), Image.LANCZOS)
	flat = Image.new("RGB", canvas.size, "#" + bg.lstrip("#"))
	flat.paste(canvas, mask=canvas.getchannel("A"))
	return flat, canvas.getchannel("A")


def extract_frames(ffmpeg: str, clip: Path, duration: float, count: int, out_dir: Path) -> list[Path]:
	out_dir.mkdir(parents=True, exist_ok=True)
	frames: list[Path] = []
	for i in range(count):
		t = duration * (i + 0.5) / count
		path = out_dir / f"frame_{i:02d}.png"
		run([ffmpeg, "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", str(clip), "-frames:v", "1", str(path)])
		frames.append(path)
	return frames


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
	board = Image.new("RGB", size, (200, 200, 200))
	for y in range(0, size[1], cell):
		for x in range((y // cell % 2) * cell, size[0], cell * 2):
			board.paste((150, 150, 150), (x, y, x + cell, y + cell))
	return board


def contact_sheet(frames: list[Path], mask: Image.Image | None, cols: int = 4) -> Image.Image:
	tiles = []
	for f in frames:
		tile = Image.open(f).convert("RGB")
		if mask is not None:
			m = mask.resize(tile.size, Image.LANCZOS)
			back = checkerboard(tile.size)
			back.paste(tile, mask=m)
			tile = back
		tiles.append(tile.resize((256, 256), Image.LANCZOS))
	rows = (len(tiles) + cols - 1) // cols
	sheet = Image.new("RGB", (cols * 256, rows * 256), (0, 0, 0))
	for i, tile in enumerate(tiles):
		sheet.paste(tile, ((i % cols) * 256, (i // cols) * 256))
	return sheet


# --- hub ---------------------------------------------------------------------

def register_artifact(http: Http, hub: str, artifact_type: str, data: bytes, ext: str, meta: dict[str, Any]) -> str:
	res = http.call(
		"POST",
		f"{hub}/artifacts",
		{"artifact_type": artifact_type, "inline_bytes_base64": base64.b64encode(data).decode("ascii"), "ext": ext, "metadata": meta},
	)
	if not res.get("id"):
		raise RuntimeError(f"hub did not store {artifact_type}: {res}")
	return str(res["id"])


def build_workflow(model: str, size: int, seed: int) -> dict[str, Any]:
	wf = copy.deepcopy(json.loads(WORKFLOW_TEMPLATE.read_text(encoding="utf-8")))
	wf[NODE_LOADER]["inputs"]["model_type"] = model
	wf[NODE_SAMPLER]["inputs"].update({"seed": seed, "width": size, "height": size})
	return wf


def submit_and_wait(http: Http, hub: str, render_request: dict[str, Any], timeout: float) -> tuple[dict[str, Any], float]:
	t0 = time.perf_counter()
	res = http.call(
		"POST",
		f"{hub}/jobs",
		{"type": "render.comfyui", "input": {"render_request": render_request}, "metadata": {"source": "story_stage_motion_spike"}},
	)
	job_id = str(res.get("id") or "")
	if not job_id:
		raise RuntimeError(f"hub did not queue the job: {res}")
	while True:
		job = http.call("GET", f"{hub}/jobs/{job_id}").get("job") or {}
		status = str(job.get("status") or "")
		if status in ("completed", "failed", "error", "cancelled"):
			return job, time.perf_counter() - t0
		if time.perf_counter() - t0 > timeout + 30:
			raise TimeoutError(f"job {job_id} still {status} after {timeout + 30:.0f}s")
		time.sleep(0.5)


def uri_to_path(uri: str) -> Path:
	p = unquote(urlparse(uri).path) if uri.startswith("file://") else uri
	if len(p) > 2 and p[0] == "/" and p[2] == ":":
		p = p[1:]
	return Path(p)


# --- commands ----------------------------------------------------------------

def cmd_check(http: Http, comfy: str, source: str, hub: str) -> int:
	ok = True
	try:
		health = http.call("GET", f"{hub}/health", timeout=5)
		print(f"hub      {hub}  ok={health.get('ok')}")
	except (URLError, RuntimeError, OSError) as e:
		ok = False
		print(f"hub      {hub}  UNREACHABLE ({e})")
	if not comfy:
		print("comfyui  no address found; pass --comfy-url or set render.comfy_url in the client config")
		return 1
	print(f"comfyui  {comfy}  (from {source})")
	try:
		stats = http.call("GET", f"{comfy}/system_stats", timeout=8)
		for dev in stats.get("devices", []):
			vram = float(dev.get("vram_total") or 0) / 2**30
			print(f"         device {dev.get('name')}  VRAM {vram:.1f} GB")
	except (URLError, RuntimeError, OSError) as e:
		print(f"         UNREACHABLE from this machine ({e}); the hub must be able to reach it")
		return 1
	for node in FLASHHEAD_NODES:
		try:
			present = bool(http.call("GET", f"{comfy}/object_info/{quote(node)}", timeout=15))
		except (URLError, RuntimeError, OSError):
			present = False
		ok = ok and present
		print(f"         {'found  ' if present else 'MISSING'} {node}")
	if not ok:
		print("\nInstall HM-RunningHub/ComfyUI_RH_FlashHead on the ComfyUI machine; see README.md.")
	return 0 if ok else 1


def cmd_run(args: argparse.Namespace, http: Http, comfy: str, hub: str) -> int:
	ffmpeg = args.ffmpeg or shutil.which("ffmpeg") or "ffmpeg"
	ffprobe = str(Path(ffmpeg).with_name("ffprobe" + Path(ffmpeg).suffix)) if args.ffmpeg else (shutil.which("ffprobe") or "ffprobe")
	audio_src = Path(args.audio) if args.audio else newest_tts_audio()
	if audio_src is None or not audio_src.exists():
		print("No --audio given and no TTS artifact found under Documents/Synesyn/Workspaces.")
		return 1
	out = Path(args.out) if args.out else HERE / "results" / time.strftime("%Y%m%d_%H%M%S")
	out.mkdir(parents=True, exist_ok=True)

	portrait, mask = prepare_portrait(Path(args.portrait), args.size, parse_crop(args.crop), args.bg)
	portrait.save(out / "portrait_input.png")
	mask.save(out / "portrait_mask.png")
	wav = out / "line.wav"
	run([ffmpeg, "-v", "error", "-y", "-i", str(audio_src), "-ac", "1", "-ar", "16000", str(wav)])
	audio_sec = probe(ffprobe, wav)["duration_sec"]

	buf = io.BytesIO()
	portrait.save(buf, format="PNG")
	def meta(source: Path) -> dict[str, Any]:
		return {"provenance": {"generated_by": "story_stage_motion_spike", "source": str(source.resolve())}}

	portrait_id = register_artifact(http, hub, "image.story_stage_portrait", buf.getvalue(), "png", meta(Path(args.portrait)))
	audio_id = register_artifact(http, hub, "audio.story_stage_line", wav.read_bytes(), "wav", meta(audio_src))
	print(f"line {audio_sec:.2f}s  portrait {portrait_id}  audio {audio_id}")

	runs: list[dict[str, Any]] = []
	last_clip: Path | None = None
	for i in range(args.runs):
		rr = {
			"routing": {"mode": "hub", "provider": "comfyui", "comfy_base_url": comfy},
			"client": {"client_id": "story_stage_spike", "request_id": f"spike_{out.name}_{i}"},
			"workflow": {"inline": build_workflow(args.model, args.size, args.seed + i)},
			"input_uploads": [
				{"node_id": NODE_IMAGE, "input": "image", "artifact_id": portrait_id, "filename": f"{portrait_id}.png", "subfolder": args.upload_subfolder},
				{"node_id": NODE_AUDIO, "input": "audio", "artifact_id": audio_id, "filename": f"{audio_id}.wav", "subfolder": args.upload_subfolder},
			],
			"output_routing": {"videos": {"artifact_type": "video.story_stage_spike"}},
			"timeout_sec": args.timeout,
		}
		job, wall = submit_and_wait(http, hub, rr, args.timeout)
		entry: dict[str, Any] = {"run": i, "wall_sec": round(wall, 2), "status": job.get("status"), "job_id": job.get("id")}
		if job.get("status") != "completed":
			entry["error"] = job.get("error")
			runs.append(entry)
			print(f"run {i}: {job.get('status')}  {job.get('error')}")
			break
		videos = [a for a in (job.get("artifacts") or []) if str(a.get("artifact_type", "")).startswith("video.")]
		if not videos:
			entry["error"] = "job completed without a video output; check SaveVideo in the workflow"
			runs.append(entry)
			print(f"run {i}: {entry['error']}")
			break
		clip = out / f"clip_{i}.mp4"
		shutil.copyfile(uri_to_path(str(videos[0]["uri"])), clip)
		info = probe(ffprobe, clip)
		entry.update(info)
		entry["real_time_factor"] = round(wall / audio_sec, 3) if audio_sec else None
		entry["audio_covered"] = round(info["duration_sec"] / audio_sec, 3) if audio_sec else None
		runs.append(entry)
		last_clip = clip
		print(f"run {i}: {wall:.1f}s for {audio_sec:.2f}s of speech  (x{entry['real_time_factor']})  {info['width']}x{info['height']} @ {info['fps']} fps")

	results: dict[str, Any] = {
		"comfy_url": comfy,
		"hub_url": hub,
		"model": args.model,
		"size": args.size,
		"portrait": str(Path(args.portrait).resolve()),
		"audio": str(audio_src.resolve()),
		"audio_sec": round(audio_sec, 3),
		"runs": runs,
	}
	if last_clip is not None:
		ogv = last_clip.with_suffix(".ogv")
		run([ffmpeg, "-v", "error", "-y", "-i", str(last_clip), "-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "5", str(ogv)])
		frames = extract_frames(ffmpeg, last_clip, probe(ffprobe, last_clip)["duration_sec"], 8, out / "frames")
		contact_sheet(frames, None).save(out / "contact_sheet.png")
		contact_sheet(frames, mask).save(out / "contact_sheet_masked.png")
		warm = [r["real_time_factor"] for r in runs[1:] if r.get("real_time_factor")]
		results["godot_clip"] = ogv.name
		results["warm_real_time_factor"] = round(sum(warm) / len(warm), 3) if warm else None
		results["verdict_hint"] = verdict_hint(results["warm_real_time_factor"] or runs[0].get("real_time_factor"))
	(out / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
	print(f"\nresults in {out}")
	if results.get("verdict_hint"):
		print(results["verdict_hint"])
	return 0 if last_clip is not None else 1


def verdict_hint(rtf: float | None) -> str:
	if rtf is None:
		return ""
	if rtf <= 1.0:
		return f"x{rtf}: faster than speech; a clip per line can play with the voice (short lead-in)."
	if rtf <= 3.0:
		return f"x{rtf}: usable if the line is generated while the previous one plays (pre-roll)."
	return f"x{rtf}: too slow for live lines; keep for offline portrait sheets and replays."


def newest_tts_audio() -> Path | None:
	found = sorted(SYNESYN_DOCS.glob("Workspaces/*/artifacts/audio/tts/*.mp3"), key=lambda p: p.stat().st_mtime, reverse=True)
	return found[0] if found else None


def main(argv: list[str] | None = None) -> int:
	ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[1], formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--check", action="store_true", help="only check that the hub, ComfyUI and the FlashHead nodes are reachable")
	ap.add_argument("--comfy-url", default="", help="ComfyUI address as the hub sees it, e.g. http://100.116.159.18:8188")
	ap.add_argument("--hub-url", default="", help="hub address (default: hub.base_url from the client config)")
	ap.add_argument("--portrait", default=str(DEFAULT_PORTRAIT), help="RGBA character sprite")
	ap.add_argument("--audio", default="", help="spoken line (mp3/wav); default: newest TTS artifact")
	ap.add_argument("--crop", default="", help="x,y,w,h in sprite pixels; default: square from the top of the silhouette")
	ap.add_argument("--bg", default="808080", help="flat background colour behind the sprite, hex")
	ap.add_argument("--size", type=int, default=512, help="square output size, multiple of 8")
	ap.add_argument("--model", choices=("lite", "pro"), default="lite")
	ap.add_argument("--runs", type=int, default=2, help="the first run includes model loading; later runs are warm")
	ap.add_argument("--seed", type=int, default=42)
	ap.add_argument("--timeout", type=float, default=600.0, help="seconds the hub waits for one clip")
	ap.add_argument("--upload-subfolder", default="synesyn", help="ComfyUI input subfolder for the uploads; '' for the input root")
	ap.add_argument("--ffmpeg", default="", help="path to ffmpeg (ffprobe is expected beside it)")
	ap.add_argument("--out", default="", help="output folder (default: results/<timestamp> beside this script)")
	args = ap.parse_args(argv)

	cfg = load_client_config()
	hub_cfg = cfg.get("hub") if isinstance(cfg.get("hub"), dict) else {}
	auth = hub_cfg.get("auth") if isinstance(hub_cfg.get("auth"), dict) else {}
	http = Http(str(auth.get("token") or "") if auth.get("enabled") else "")
	comfy, source, hub = resolve_urls(args, cfg)
	if args.check:
		return cmd_check(http, comfy, source, hub)
	if not comfy:
		print("No ComfyUI address found; pass --comfy-url or set render.comfy_url in the client config.")
		return 1
	if args.size % 8:
		print("--size must be a multiple of 8")
		return 1
	return cmd_run(args, http, comfy, hub)


if __name__ == "__main__":
	sys.exit(main())
