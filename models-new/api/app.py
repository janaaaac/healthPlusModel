from flask import Flask, request, jsonify
from PIL import Image
import torch
from torchvision import transforms, models

app = Flask(__name__)

# List all your class names (one per food class/folder)
class_names = [
    'beatroot', 'beef_carpaccio', 'beef_tartare', 'beet_salad', 'cheesecake',
    'chicken curry', 'chicken_wings', 'dhal', 'french_fries', 'fried egg',
    'fried_rice', 'ice_cream', 'kottu', 'milk rice', 'omelette', 'red_rice',
    'sambol', 'white_rice'
]
num_classes = len(class_names)

# Load the TorchScript model
model = torch.jit.load(r'/Users/jana/Documents/GitHub/final-one/models-new/saved_model.pt', map_location='cpu')
model.eval()

def your_predict_function(image):
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])  # ImageNet normalization
    ])
    img_tensor = transform(image).unsqueeze(0)
    with torch.no_grad():
        output = model(img_tensor)
        _, pred = torch.max(output, 1)
        return class_names[pred.item()]

@app.route('/predict', methods=['POST'])
def predict():
    file = request.files['file']
    image = Image.open(file.stream).convert("RGB")
    result = your_predict_function(image)
    return jsonify({'result': result})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002)