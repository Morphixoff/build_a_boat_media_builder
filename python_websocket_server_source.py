# Извиняюсь за говнокод, но мне было впадлу выдумывать структуру, тестовый вариант ставший релизом.

import asyncio, websockets, os, imageio
import webbrowser as wb
from PIL import Image
from math import ceil

cached_images = {}

def get_image_size(img_name):
    image = Image.open("workspace\\"+img_name)
    return image.size

def get_video_size(video_name):
    y, x, _ =  imageio.get_reader("workspace\\"+video_name, format="ffmpeg" if video_name.endswith(".mp4") else None).get_data(0).shape
    return (x,y)

def get_pixel_color(img_name,x,y):
    if not cached_images.get(img_name):
        image = Image.open("workspace\\"+img_name)
        color = image.getpixel((x,y))
        cached_images[img_name] = image
        return f"Color3.fromRGB({color[0]},{color[1]},{color[2]})"
    else:
        image = cached_images[img_name]
        color = image.getpixel((x,y))
        return f"Color3.fromRGB({color[0]},{color[1]},{color[2]})"

async def handler(websocket):
    async for message in websocket:
        if message == "ping":
            await websocket.send(f"PONG!")
        if message.find("get_size:") != -1:
            x,y = get_image_size(message.split(":")[-1])
            await websocket.send(f"{x},{y}")
        if message.find("get_video_size") != -1:
            x,y = get_video_size(message.split(":")[-1])
            await websocket.send(f"{x},{y}")
        if message.find("get_pixel:") != -1:
            image,x,y = message.split(":")[1:]
            await websocket.send(get_pixel_color(image,int(x),int(y)))
        if message.find("get_files") != -1:
            Output = ""
            for i in [os.path.join(dirpath,f) for (dirpath, dirnames, filenames) in os.walk("workspace\\") for f in filenames]:
                Output = Output + (i.replace("workspace\\","",1).replace("\\","\\\\") + ",")
            await websocket.send(Output)
        if message.find("stream_image:") != -1:
            image_name,resize = message.split(":")[1:]
            resize = int(resize)
            image = Image.open("workspace\\"+image_name).convert("RGB")
            image_size = image.size
            image_pixels = image.load()
            output = ""
            for y in range(0,image_size[1],resize):
                for x in range(0,image_size[0],resize):
                    r,g,b = image_pixels[x,y]
                    output += f"{x}:{y}:{r}:{g}:{b},"
                    if len(output) >= 1000000:
                        await websocket.send(output)
                        output = ""
            if output != "":
                await websocket.send(output)
            await websocket.send("stream_end")
            print(f"Sucessfuly streamed {image_name} into your roblox!")
        if message.find("stream_video:") != -1:
            filename, resize = message.split(":")[1:]
            for _, image in enumerate(imageio.get_reader("workspace\\"+filename, format="ffmpeg" if filename.split(".")[-1] != "gif" else None)):
                image = Image.fromarray(image).convert("RGB")
                image_pixels = image.load()
                sizeX, sizeY = image.size
                resize = int(resize)
                output = ""
                for y in range(0, sizeY, resize):
                    for x in range(0, sizeX, resize):
                        r, g, b = image_pixels[x,y]
                        output += f"{x}:{y}:{r}:{g}:{b},"
                await websocket.send(output)
            await websocket.send("stream_end")
            print(f"Sucessfuly streamed video {filename} into your roblox!")

async def main():
    async with websockets.serve(handler, "localhost", 8000):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
