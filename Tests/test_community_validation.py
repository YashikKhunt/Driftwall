import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("validator", Path(__file__).parents[1] / "scripts" / "validate-community.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def setup(root, **changes):
    community = root / "Community"
    assets = community / "Assets"
    assets.mkdir(parents=True)
    payload = b"video"
    (assets / "sample.mp4").write_bytes(payload)
    item = {"id":"community-sample", "title":"Sample", "description":"A sample", "artist":"Contributor", "license":"CC0-1.0", "category":"Nature", "filename":"sample.mp4", "sha256":hashlib.sha256(payload).hexdigest()}
    item.update(changes)
    (community / "catalog.json").write_text(json.dumps({"schemaVersion":1, "wallpapers":[item]}))
    return community


class ValidationTests(unittest.TestCase):
    def valid(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        community = setup(Path(directory.name))
        self.assertEqual(validator.validate(community), 1)
        return community

    def rejected(self, **changes):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        with self.assertRaises(ValueError):
            validator.validate(setup(Path(directory.name), **changes))

    def test_valid(self): self.valid()
    def test_bad_id(self): self.rejected(id="community--bad")
    def test_long_id(self): self.rejected(id="community-" + "a" * 71)
    def test_empty_title(self): self.rejected(title="  ")
    def test_bidi_title(self): self.rejected(title="bad\u202ename")
    def test_bad_license_type(self): self.rejected(license=1)
    def test_bad_category_type(self): self.rejected(category=[])
    def test_traversal_filename(self): self.rejected(filename="../bad.mp4")
    def test_long_filename(self): self.rejected(filename="a" * 157 + ".mp4")
    def test_bad_hash(self): self.rejected(sha256="0" * 64)
    def test_profile_credentials(self): self.rejected(profileURL="https://user@example.com")
    def test_profile_query(self): self.rejected(profileURL="https://example.com/?x=1")
    def test_unknown_key(self):
        community = self.valid(); p = community / "catalog.json"; data = json.loads(p.read_text()); data["wallpapers"][0]["x"] = 1; p.write_text(json.dumps(data))
        with self.assertRaises(ValueError): validator.validate(community)
    def test_duplicate_json_key(self):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup); community = setup(Path(directory.name)); (community / "catalog.json").write_text('{"schemaVersion":1,"schemaVersion":1,"wallpapers":[]}')
        with self.assertRaises(ValueError): validator.validate(community)
    def test_unexpected_asset(self):
        community = self.valid(); (community / "Assets" / "extra.mov").write_bytes(b"x")
        with self.assertRaises(ValueError): validator.validate(community)
    def test_zero_byte_asset(self):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup); community = setup(Path(directory.name)); (community / "Assets" / "sample.mp4").write_bytes(b"")
        with self.assertRaises(ValueError): validator.validate(community)
    def test_asset_symlink(self):
        community = self.valid(); asset = community / "Assets" / "sample.mp4"; target = community / "Assets" / "target.mp4"; asset.rename(target); asset.symlink_to(target.name)
        with self.assertRaises(ValueError): validator.validate(community)
    def test_catalog_symlink(self):
        community = self.valid(); catalog = community / "catalog.json"; target = community / "catalog.real"; catalog.rename(target); catalog.symlink_to(target.name)
        with self.assertRaises(ValueError): validator.validate(community)
    def test_file_size_limit(self):
        old = validator.MAX_FILE; validator.MAX_FILE = 3
        try:
            with tempfile.TemporaryDirectory() as d:
                with self.assertRaises(ValueError): validator.validate(setup(Path(d)))
        finally: validator.MAX_FILE = old
    def test_gitkeep_directory(self):
        community = self.valid(); (community / "Assets" / ".gitkeep").mkdir()
        with self.assertRaises(ValueError): validator.validate(community)

if __name__ == "__main__": unittest.main()
