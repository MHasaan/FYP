# 📝 Project TODO List

This document tracks the progress, completed tasks, and upcoming goals for the **FYP Fall Detection System**.

---

## 🚀 Current Status: Stable (Testing Phase)
The core pipeline is integrated and the backend is now successfully registering detections.

---

## ✅ Completed Tasks
- [x] **Core ML Integration**: RTMPose, Patch Extraction, and VSViG models merged into `ml_manager`.
- [x] **Direct Verification**: Verified that the model detects falls in `fall.avi` and `fall2.mp4` with >95% confidence.
- [x] **Backend Registration**: Implemented `ResultProcessor` to save detections to the database.
- [x] **Alert System**: Seeded a default "Global Fall Detection" alert rule (Threshold: 0.5).
- [x] **Circular Import Fix**: Resolved the startup crash in the backend `database.py`.
- [x] **Session Linkage**: Fixed the bug where detections weren't appearing in the UI due to missing `session_id`.
- [x] **Premium UI Design**: Applied glassmorphism and theme support to the frontend.

---

## 🏃 In Progress
- [ ] **Real-world Verification**: Confirming that the UI accurately displays "FALL" alerts during a live run of the test videos.
- [ ] **Threshold Tuning**: Adjusting the 0.5 threshold to minimize false positives while maintaining safety.
- [ ] **UI Refresh**: Ensuring the "History" and "Activity Logs" are updating in real-time.

---

## 📅 Upcoming Goals
- [ ] **RTSP Stream Integration**: Test with a live IP camera stream instead of video files.
- [ ] **Notification System**: Expand the alert actions to include real Webhooks or Emails.
- [ ] **Multi-Camera Optimization**: Stress test the `ml_manager` by running 3+ pipelines simultaneously.
- [ ] **Model Selection**: Allow users to switch between "Base" and "Light" models from the UI.
- [ ] **Edge Deployment**: Optimize the `ml_manager` for smaller GPU memory footprints.

---

## 🛠️ Maintenance & Notes
- Use `.\commandScripts\start.bat rebuild` after significant code changes.
- Check `docker compose logs -f ml-manager` for real-time probability scores.
- Use `stop.bat clean` only if you want to wipe the database and start over.

---
*Last Updated: April 28, 2026*
