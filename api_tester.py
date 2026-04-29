import requests
import json
import time

BASE_URL = "http://localhost:8000"

def test_pipeline():
    # 1. Create a Camera Config
    print("Creating Camera Config...")
    cam_data = {
        "name": "Test Script Camera",
        "source_type": "video_file",
        "source_url": "/videos/recordings/sample.mp4",
        "fps": 30,
        "width": 640,
        "height": 480,
        "enabled_models": ["pose", "fall_detection"],
        "model_configs": {}
    }
    r = requests.post(f"{BASE_URL}/api/camera/configs/", json=cam_data)
    cam = r.json()
    print("Camera:", cam)

    # 2. Create Instance
    print("Creating Instance...")
    inst_data = {
        "name": "Test Script Instance",
        "camera_config_id": cam["id"],
        "enabled_models": ["pose", "fall_detection"],
        "model_configs": {}
    }
    r = requests.post(f"{BASE_URL}/api/instances/", json=inst_data)
    inst = r.json()
    print("Instance:", inst)

    # 3. Start Instance
    print("Starting Instance...")
    r = requests.post(f"{BASE_URL}/api/instances/{inst['id']}/control", json={"action": "start"})
    print("Start Response:", r.json())
    
    time.sleep(2)
    print("Done")

if __name__ == "__main__":
    test_pipeline()
