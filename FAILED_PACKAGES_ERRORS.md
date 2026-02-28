# Failed packages – error summary

Walkthrough of the **14 failed packages** from the latest Autoware build and what caused each failure.

---

## 1. **Deprecated rclcpp subscription API** (`-Werror=deprecated-declarations`)

**Cause:** Code uses the old callback form `void(std::shared_ptr<MessageT>)`. ROS 2 Humble/rclcpp warns and recommends `void(std::shared_ptr<const MessageT>)`. With **warnings as errors**, the build fails.

**Fix options:**  
- Change each subscription callback to take `std::shared_ptr<const MessageT>` (and use `const` in the implementation), **or**  
- Add `-Wno-deprecated-declarations` (or equivalent) for these packages so the warning does not turn into an error.

**Affected packages (7):**

| Package | Failing file(s) / note |
|--------|-------------------------|
| `autoware_test_utils` | `topic_snapshot_saver.cpp` – multiple `create_subscription` callbacks |
| `autoware_path_sampler` | `node.cpp` – Path subscription callback |
| `autoware_vehicle_cmd_gate` | `vehicle_cmd_gate.cpp` – Odometry, Accel, PredictedObjects, OperationModeState, LaneletRoute, TrafficLightGroupArray, TrackedObjects, PathWithLaneId |
| `autoware_calibration_status_classifier` | `calibration_status_classifier_node.cpp` – Twist, TwistStamped, TwistWithCovariance, TwistWithCovarianceStamped |
| `autoware_kinematic_evaluator` | `kinematic_evaluator_node.cpp` – Odometry callback |
| `autoware_predicted_path_checker` | `predicted_path_checker_node.cpp` – Trajectory, Odometry, etc. |
| `autoware_planning_rviz_plugin` | `display_base.cpp` – CandidateTrajectories, ScoredCandidateTrajectories subscription lambdas |

---

## 2. **PCL 1.12 – anonymous structs / pedantic** (`-Werror=pedantic`)

**Cause:** System PCL headers (`/usr/include/pcl-1.12/pcl/impl/point_types.hpp`) use anonymous structs/unions and extra semicolons. With **pedantic warnings as errors**, the build fails when your code includes PCL.

**Fix options:**  
- Treat PCL include path as **SYSTEM** and/or add for the targets that use PCL:  
  `-Wno-pedantic` and `-Wno-error=pedantic` (so PCL’s style doesn’t trigger errors).

**Affected packages (3):**

| Package | Failing file(s) |
|--------|------------------|
| `yabloc_image_processing` | `line_segment_detector_core.cpp` (via `line_segment_detector.hpp` → PCL `point_types.hpp`) |
| `autoware_lidar_marker_localizer` | `lidar_marker_localizer.cpp` (via `lidar_marker_localizer.hpp` → PCL `transforms.h` → `point_types.hpp`) |
| `autoware_perception_online_evaluator` | `metrics_calculator.cpp` (via object_recognition_utils → PCL) |

---

## 3. **autoware_lidar_centerpoint – macro redefinition** (`-Werror`)

**Cause:** `CHECK_CUDA_ERROR` is defined in two places and both end up in the same compile unit:

- `autoware/install/autoware_cuda_utils/include/.../cuda_check_error.hpp:42`  
- `autoware_lidar_centerpoint/include/autoware/lidar_centerpoint/cuda_utils.hpp:52`

So you get: **"CHECK_CUDA_ERROR redefined"** and with `-Werror` the build fails.

**Fix options:**  
- In `autoware_lidar_centerpoint`, don’t define `CHECK_CUDA_ERROR` if it’s already defined (e.g. `#ifndef CHECK_CUDA_ERROR` / `#define` / `#endif`), **or**  
- Use only one of the two headers (prefer `autoware_cuda_utils` and remove the local macro), **or**  
- For this package only, disable the warning that triggers the error (e.g. do not treat this redefinition as error).

---

## 4. **autoware_traffic_light_classifier** – TensorRT / conv profiler

**Cause:** Two issues:

1. **Narrowing conversion** (`-Werror=narrowing`):  
   `autoware_tensorrt_common/conv_profiler.hpp:98` – `in_dim.d[1]`, `out_dim.d[1]`, etc. (`int64_t`) are passed where `int` is expected (e.g. into a struct or initializer that uses `int`).

2. **Deprecated TensorRT API:**  
   `IInt8Calibrator` is deprecated in the TensorRT headers you’re using.

**Fix options:**  
- In `conv_profiler.hpp` (and any callers), use explicit casts to `int` where the value is known to fit (e.g. `static_cast<int>(in_dim.d[1])`) so the narrowing warning is resolved or allowed.  
- For the deprecated API: either switch to the non-deprecated API or, for this package only, allow deprecated-declarations (e.g. `-Wno-deprecated-declarations` for this file or target).

---

## 5. **autoware_traffic_light_fine_detector** – same TensorRT narrowing

**Cause:** Same as **autoware_traffic_light_classifier**:  
`autoware_tensorrt_common/conv_profiler.hpp:98` – narrowing from `int64_t` to `int` with `-Werror=narrowing`.

**Fix options:**  
- Same as above: cast to `int` in `conv_profiler.hpp` (or in the caller) so the initializer is valid and the warning goes away, or relax the warning for this code.

---

## 6. **autoware_elevation_map_loader** – missing deps / linker

**Cause:**  
- **CMake:** `find_package(rosbag2_storage_sqlite3)` fails – no `rosbag2_storage_sqlite3Config.cmake` (or `-config.cmake`) found.  
- **Linker:**  
  `cannot find -lopencv_alphamat`, `-lopencv_barcode`, `-lopencv_hdf`, `-lopencv_viz`  
  So the build fails at link time due to missing OpenCV extra modules.

**Fix options:**  
- Install ROS 2 package that provides `rosbag2_storage_sqlite3` (e.g. `ros-humble-rosbag2-storage-default-plugins` or the specific sqlite3 package if it exists).  
- Install OpenCV (and the **opencv_contrib** modules that provide `alphamat`, `barcode`, `hdf`, `viz`) so that the linker finds these libraries, or adjust the package’s `CMakeLists.txt` to not require them if you don’t need that functionality.

---

## 7. **autoware_calibration_status_classifier** – deprecated rclcpp (see above)

Already covered in **§ 1**.

---

## Summary table

| # | Package | Error type | Fix direction |
|---|---------|------------|----------------|
| 1 | autoware_test_utils | rclcpp deprecated subscription | Update callbacks to `shared_ptr<const T>` or add `-Wno-deprecated-declarations` |
| 2 | autoware_path_sampler | rclcpp deprecated subscription | Same |
| 3 | autoware_vehicle_cmd_gate | rclcpp deprecated subscription | Same |
| 4 | autoware_lidar_centerpoint | CHECK_CUDA_ERROR redefined | Unify macro (e.g. guard or use only autoware_cuda_utils) |
| 5 | yabloc_image_processing | PCL pedantic (anonymous structs) | PCL as SYSTEM and/or `-Wno-pedantic` for this package |
| 6 | autoware_lidar_marker_localizer | PCL pedantic | Same |
| 7 | autoware_traffic_light_classifier | TensorRT narrowing + deprecated IInt8Calibrator | Casts in conv_profiler.hpp; allow deprecated or update API |
| 8 | autoware_elevation_map_loader | Missing rosbag2_sqlite3 + OpenCV libs | Install rosbag2 sqlite3 pkg and OpenCV (contrib) libs |
| 9 | autoware_perception_online_evaluator | PCL pedantic | Same as 5–6 |
| 10 | autoware_traffic_light_fine_detector | TensorRT narrowing (conv_profiler) | Same as 7 (conv_profiler.hpp) |
| 11 | autoware_calibration_status_classifier | rclcpp deprecated subscription | Same as 1–3 |
| 12 | autoware_kinematic_evaluator | rclcpp deprecated subscription | Same |
| 13 | autoware_predicted_path_checker | rclcpp deprecated subscription | Same |
| 14 | autoware_planning_rviz_plugin | rclcpp deprecated subscription | Same |

---

## Grouped fixes (what to do first)

1. **Global or per-package warning flags (quick path)**  
   - In your build (e.g. `build_autoware.sh` or colcon args), add CMake flags so that for the **whole workspace** or for the failing packages you pass:  
     - `-Wno-deprecated-declarations` (for rclcpp)  
     - `-Wno-pedantic` / `-Wno-error=pedantic` (for PCL)  
     - And, if needed, a flag to not treat the macro redefinition as error for `autoware_lidar_centerpoint`.  
   That will unblock all 14 packages without changing Autoware or TensorRT code (at the cost of hiding those warnings).

2. **Dependency and linker (autoware_elevation_map_loader)**  
   - Install `ros-humble-rosbag2-storage-default-plugins` (and/or the specific sqlite3 package).  
   - Install OpenCV with contrib (alphamat, barcode, hdf, viz) and ensure they are in the link line.

3. **Code/header fixes (proper fix)**  
   - **rclcpp:** In each of the 7 packages, change subscription callbacks to `void(std::shared_ptr<const MessageT>)` and update the implementation accordingly.  
   - **PCL:** In the 3 packages that include PCL, add PCL as SYSTEM include and/or add `-Wno-pedantic` for those targets.  
   - **autoware_lidar_centerpoint:** Remove or guard the duplicate `CHECK_CUDA_ERROR` so only one definition is visible.  
   - **TensorRT:** In `autoware_tensorrt_common` (or in the install that provides `conv_profiler.hpp`), fix the narrowing in line 98 (e.g. `static_cast<int>(in_dim.d[1])` etc.) and optionally address the deprecated IInt8Calibrator usage.

If you tell me which route you prefer (quick flags vs. code fixes), I can outline exact patch steps or CMake/colcon changes next.
