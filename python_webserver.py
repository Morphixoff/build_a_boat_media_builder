import base64, timeit
from fastapi import FastAPI, HTTPException
from PIL import Image
from PIL.ImageFile import ImageFile
from pathlib import Path
from os import mkdir
from imageio import get_reader
from time import perf_counter

app = FastAPI()
cwd = Path.cwd()
workspace_path = cwd / "workspace"
workspace_path.mkdir(exist_ok=True)

def get_image_shape(image: ImageFile):
    x,y = image.size
    return f"{x}:{y}"

def get_video_shape(video_path: Path):
    video_format = "ffmpeg" if video_path.suffix != ".gif" else None
    reader = get_reader(video_path, video_format)

    with reader:
        y, x, _ = reader.get_data(0).shape
        return f"{x}:{y}"

def get_media_shape(file_path: Path):
    if file_path.suffix in (".png", ".jpeg", ".jpg"):
        return get_image_shape(Image.open(file_path))
    else:
        return get_video_shape(file_path)


def get_image_bytes(image: ImageFile, compression: int):
    converted_image = image.convert("RGB")
    image_size = converted_image.size
    image_pixels = converted_image.load()
    data = bytearray()

    for y in range(0, image_size[1], compression):
        for x in range(0, image_size[0], compression):
            r,g,b = image_pixels[x,y]
            data.extend((r,g,b))

    return base64.b64encode(data).decode('ascii')

def get_image_text(image: ImageFile, compression: int):
    converted_image = image.convert("RGB")
    image_size = converted_image.size
    image_pixels = converted_image.load()
    pixels = []

    for y in range(0, image_size[1], compression):
        for x in range(0, image_size[0], compression):
            r,g,b = image_pixels[x,y]
            pixels.append(f"{r}:{g}:{b}")

    return ",".join(pixels)

def get_image_data(image: ImageFile, compression: int, use_bytes: bool = True) -> str:
    return get_image_bytes(image, compression) if use_bytes else get_image_text(image, compression)

def get_video_data(video_path: Path, compression: int, use_bytes: bool) -> str:
    
    video_format = "ffmpeg" if video_path.suffix != ".gif" else None

    with get_reader(video_path, video_format) as reader:
        data = "|".join(get_image_data(Image.fromarray(image), compression, use_bytes) for image in reader)
        return data

def get_media_data(file_path: Path, compression: int, use_bytes: bool) -> str:
    if file_path.suffix in (".png", ".jpeg", ".jpg"):
        return get_image_data(Image.open(file_path), compression, use_bytes)
    else:
        return get_video_data(file_path, compression, use_bytes)

def get_files():
    if not workspace_path.exists():
        raise HTTPException(status_code=400, detail="workspace folder is not present in server directory")

    return ",".join(elem.name for elem in workspace_path.iterdir())
    

def find_file(name: str):
    if not workspace_path.exists():
        raise HTTPException(status_code=400, detail="workspace folder is not present in server directory")

    file_path = workspace_path / name

    if not file_path.exists():
        raise HTTPException(status_code=400, detail="file not found")

    return file_path

@app.get("/shape")
def send_media_shape(name: str):
    return get_media_shape(find_file(name))

@app.get("/media")
def send_media(name: str, compression: int, use_bytes: bool = False):
    file_path = find_file(name)

    ot = perf_counter()
    media = get_media_data(file_path, compression, use_bytes)
    ot2 = perf_counter()

    print(f"Файл {name} успешно передан за {round(ot2-ot, 2)} сек.")
    return media

@app.get("/files")
def send_files():
    return get_files()