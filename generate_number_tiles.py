#
# generate_number_tiles.py
#
# Generates number labels in 32x32 images.
#

from PIL import Image, ImageDraw, ImageFont
import os

# https://stackoverflow.com/questions/77038132/python-pillow-pil-doesnt-recognize-the-attribute-textsize-of-the-object-imag
def textsize(text, font):
    im = Image.new(mode="P", size=(0, 0))
    draw = ImageDraw.Draw(im)
    _, _, width, height = draw.textbbox((0, 0), text=text, font=font)
    return width, height

# Create output directory if it doesn't exist
os.makedirs("output", exist_ok=True)

# Set up font
font = ImageFont.truetype("arial.ttf", 20)

for i in range(64):
    # Create a new black image
    img = Image.new('RGB', (32, 32), color='black')

    # Create a draw object
    draw = ImageDraw.Draw(img)

    # Add the number to the image
    text = str(i)
    text_width, text_height = textsize(text, font=font)
    position = ((32-text_width)//2, (32-text_height)//2)
    draw.text(position, text, fill='white', font=font)

    # Save the image
    img.save(f"output/{i}.png")