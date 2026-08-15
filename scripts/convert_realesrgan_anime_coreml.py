#!/usr/bin/env python3
"""Convert the official RealESRGAN_x4plus_anime_6B weights to a tiled iOS model."""

from __future__ import annotations

import argparse
import hashlib
import urllib.request
from pathlib import Path

import coremltools as ct
import torch
from torch import nn
from torch.nn import functional as F


WEIGHTS_URL = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/"
    "v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth"
)
WEIGHTS_SHA256 = "f872d837d3c90ed2e05227bed711af5671a6fd1c9f7d7e91c911a61f155e99da"
TILE_SIZE = 128


class ResidualDenseBlock(nn.Module):
    def __init__(self, features: int = 64, growth: int = 32) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(features, growth, 3, 1, 1)
        self.conv2 = nn.Conv2d(features + growth, growth, 3, 1, 1)
        self.conv3 = nn.Conv2d(features + 2 * growth, growth, 3, 1, 1)
        self.conv4 = nn.Conv2d(features + 3 * growth, growth, 3, 1, 1)
        self.conv5 = nn.Conv2d(features + 4 * growth, features, 3, 1, 1)
        self.activation = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        x1 = self.activation(self.conv1(value))
        x2 = self.activation(self.conv2(torch.cat((value, x1), 1)))
        x3 = self.activation(self.conv3(torch.cat((value, x1, x2), 1)))
        x4 = self.activation(self.conv4(torch.cat((value, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((value, x1, x2, x3, x4), 1))
        return value + x5 * 0.2


class RRDB(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.rdb1 = ResidualDenseBlock()
        self.rdb2 = ResidualDenseBlock()
        self.rdb3 = ResidualDenseBlock()

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return value + self.rdb3(self.rdb2(self.rdb1(value))) * 0.2


class RRDBNet(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.conv_first = nn.Conv2d(3, 64, 3, 1, 1)
        self.body = nn.ModuleList([RRDB() for _ in range(6)])
        self.conv_body = nn.Conv2d(64, 64, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(64, 64, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(64, 64, 3, 1, 1)
        self.conv_hr = nn.Conv2d(64, 64, 3, 1, 1)
        self.conv_last = nn.Conv2d(64, 3, 3, 1, 1)
        self.activation = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        first = self.conv_first(value)
        body = first
        for block in self.body:
            body = block(body)
        body = self.conv_body(body) + first
        body = self.activation(self.conv_up1(F.interpolate(body, scale_factor=2, mode="nearest")))
        body = self.activation(self.conv_up2(F.interpolate(body, scale_factor=2, mode="nearest")))
        return self.conv_last(self.activation(self.conv_hr(body)))


class ImageOutputModel(nn.Module):
    """Core ML image outputs use byte-range RGB, while Real-ESRGAN emits 0...1."""

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return torch.clamp(self.model(value), 0.0, 1.0) * 255.0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_weights(path: Path) -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(WEIGHTS_URL, path)
    actual = sha256(path)
    if actual != WEIGHTS_SHA256:
        raise RuntimeError(f"unexpected weights checksum: {actual}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", type=Path, default=Path("build-model/RealESRGAN_x4plus_anime_6B.pth"))
    parser.add_argument("--output", type=Path, default=Path("RealESRGANAnimeSharp.mlpackage"))
    args = parser.parse_args()

    ensure_weights(args.weights)
    checkpoint = torch.load(args.weights, map_location="cpu", weights_only=True)
    state = checkpoint.get("params_ema", checkpoint.get("params", checkpoint))
    model = RRDBNet().eval()
    missing, unexpected = model.load_state_dict(state, strict=False)
    if missing or unexpected:
        raise RuntimeError(f"weights mismatch; missing={missing}, unexpected={unexpected}")

    wrapped = ImageOutputModel(model).eval()
    example = torch.zeros(1, 3, TILE_SIZE, TILE_SIZE)
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example)
        reference = wrapped(example)
    if tuple(reference.shape) != (1, 3, TILE_SIZE * 4, TILE_SIZE * 4):
        raise RuntimeError(f"unexpected output shape: {tuple(reference.shape)}")

    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.ImageType(
                name="input",
                shape=example.shape,
                scale=1.0 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
    )
    converted.author = "InkShelf; source model by the Real-ESRGAN project"
    converted.license = "BSD-3-Clause"
    converted.short_description = (
        "RealESRGAN_x4plus_anime_6B fixed 128px tile, 4x RGB output for local Sharp processing"
    )
    converted.user_defined_metadata["com.inkshelf.profile"] = "sharp"
    converted.user_defined_metadata["com.inkshelf.model"] = "realesrgan-x4plus-anime"
    converted.user_defined_metadata["com.inkshelf.tile-size"] = str(TILE_SIZE)
    converted.user_defined_metadata["com.inkshelf.upscale"] = "4"
    converted.save(str(args.output))


if __name__ == "__main__":
    main()
