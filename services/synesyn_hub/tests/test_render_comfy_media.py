from __future__ import annotations

import asyncio
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app.render import comfy, comfy_media


class FakeRepo:
	def __init__(self, records: dict[str, str]) -> None:
		self.records = records

	async def query(self, q):
		art_id = q["where"]["id"]
		if art_id not in self.records:
			return {"columns": ["id", "uri"], "rows": []}
		return {"columns": ["id", "uri"], "rows": [[art_id, self.records[art_id]]]}


class ComfyHelpersTests(unittest.TestCase):
	def test_ext_for_filename(self) -> None:
		self.assertEqual(comfy.ext_for_filename("clip_00001.MP4"), "mp4")
		self.assertEqual(comfy.ext_for_filename("a.jpeg"), "jpg")
		self.assertEqual(comfy.ext_for_filename("noext"), "png")
		self.assertEqual(comfy.ext_for_filename("weird.xyz"), "png")

	def test_multipart_body_carries_fields_and_file(self) -> None:
		body, content_type = comfy.multipart_body(
			{"type": "input"}, file_field="image", filename="p.png", data=b"\x89PNGdata"
		)
		self.assertTrue(content_type.startswith("multipart/form-data; boundary="))
		boundary = content_type.split("boundary=", 1)[1].encode()
		self.assertIn(boundary, body)
		self.assertIn(b'name="type"\r\n\r\ninput', body)
		self.assertIn(b'name="image"; filename="p.png"', body)
		self.assertIn(b"\x89PNGdata", body)


class OutputFilesTests(unittest.TestCase):
	OUTPUTS = {
		"9": {"images": [{"filename": "still_0001.png", "subfolder": "", "type": "output"}]},
		"5": {"videos": [{"filename": "clip_0001.mp4", "subfolder": "flash", "type": "output"}]},
		"7": {"gifs": [{"filename": "loop.webm", "type": "output"}], "text": ["ignored"]},
		"8": {"audio": [{"filename": "line.wav"}]},
	}

	def test_images_only_without_opt_in(self) -> None:
		found = comfy_media.output_files_by_node(self.OUTPUTS)
		self.assertEqual([n for n, _ in found], ["9"])
		self.assertEqual(found[0][1][0]["kind"], "image")

	def test_video_and_audio_keys_with_opt_in(self) -> None:
		routing = {"videos": {"artifact_type": "video.story_stage_line"}, "audio": {}}
		found = dict(comfy_media.output_files_by_node(self.OUTPUTS, routing))
		self.assertEqual(found["5"][0]["kind"], "video")
		self.assertEqual(found["5"][0]["subfolder"], "flash")
		self.assertEqual(found["7"][0]["kind"], "video")
		self.assertEqual(found["8"][0]["kind"], "audio")
		self.assertEqual(found["8"][0]["type"], "output")

	def test_artifact_type_for(self) -> None:
		routing = {"videos": {"artifact_type": "video.story_stage_line"}}
		self.assertEqual(comfy_media.artifact_type_for("video", routing, "image.generated"), "video.story_stage_line")
		self.assertEqual(comfy_media.artifact_type_for("video", {"videos": {}}, "image.generated"), "video.generated")
		self.assertEqual(comfy_media.artifact_type_for("video", {}, "image.generated"), "image.generated")
		self.assertEqual(comfy_media.artifact_type_for("image", routing, "image.generated"), "image.generated")


class InputUploadTests(unittest.TestCase):
	def setUp(self) -> None:
		self.tmp = tempfile.TemporaryDirectory()
		self.portrait = Path(self.tmp.name) / "didi.png"
		self.portrait.write_bytes(b"portrait-bytes")
		self.repo = FakeRepo({"art_portrait": self.portrait.as_uri()})
		self.workflow = {"4": {"class_type": "LoadImage", "inputs": {"image": "placeholder.png"}}}

	def tearDown(self) -> None:
		self.tmp.cleanup()

	def test_uploads_and_patches_node(self) -> None:
		calls = []

		async def fake_upload(base_url, data, *, filename, subfolder="synesyn"):
			calls.append((base_url, data, filename, subfolder))
			return f"{subfolder}/{filename}"

		uploads = [{"node_id": "4", "input": "image", "artifact_id": "art_portrait", "filename": "didi.png"}]
		with patch.object(comfy, "upload_input", fake_upload):
			wf = asyncio.run(comfy_media.apply_input_uploads("http://comfy:8188", self.workflow, uploads, repo=self.repo))
		self.assertEqual(wf["4"]["inputs"]["image"], "synesyn/didi.png")
		self.assertEqual(self.workflow["4"]["inputs"]["image"], "placeholder.png")
		self.assertEqual(calls, [("http://comfy:8188", b"portrait-bytes", "didi.png", "synesyn")])

	def test_no_uploads_returns_workflow_unchanged(self) -> None:
		wf = asyncio.run(comfy_media.apply_input_uploads("http://comfy:8188", self.workflow, None, repo=self.repo))
		self.assertIs(wf, self.workflow)

	def test_missing_node_or_artifact_raises(self) -> None:
		bad_node = [{"node_id": "99", "input": "image", "artifact_id": "art_portrait"}]
		with self.assertRaises(ValueError):
			asyncio.run(comfy_media.apply_input_uploads("http://comfy:8188", self.workflow, bad_node, repo=self.repo))
		bad_art = [{"node_id": "4", "input": "image", "artifact_id": "art_missing"}]
		with self.assertRaises(ValueError):
			asyncio.run(comfy_media.apply_input_uploads("http://comfy:8188", self.workflow, bad_art, repo=self.repo))


if __name__ == "__main__":
	unittest.main()
