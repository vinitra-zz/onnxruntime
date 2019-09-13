#!/bin/bash
set -e -o -x

SCRIPT_DIR="$( dirname "${BASH_SOURCE[0]}" )"
SOURCE_ROOT=$(realpath $SCRIPT_DIR/../../../../)
CUDA_VER=cuda10.0-cudnn7.3

while getopts c:o:d:r:p:x:a:v: parameter_Option
do case "${parameter_Option}"
in
#android, ubuntu16.04, manylinux2010
o) BUILD_OS=${OPTARG};;
#cpu, gpu, tensorrt
d) BUILD_DEVICE=${OPTARG};;
r) BUILD_DIR=${OPTARG};;
#python version: 3.6 3.7 (absence means default 3.5)
p) PYTHON_VER=${OPTARG};;
# "--build_wheel --use_openblas"
x) BUILD_EXTR_PAR=${OPTARG};;
# "cuda10.0-cudnn7.3, cuda9.1-cudnn7.1"
c) CUDA_VER=${OPTARG};;
# x86 or other, only for ubuntu16.04 os
a) BUILD_ARCH=${OPTARG};;
# openvino version tag: 2018_R5, 2019_R1.1 (Default is 2019_R1.1)
v) OPENVINO_VERSION=${OPTARG};;
esac
done

EXIT_CODE=1
PYTHON_VER=${PYTHON_VER:=3.5}
echo "bo=$BUILD_OS bd=$BUILD_DEVICE bdir=$BUILD_DIR pv=$PYTHON_VER bex=$BUILD_EXTR_PAR"

cd $SCRIPT_DIR/docker
if [ $BUILD_OS = "android" ]; then
    IMAGE="android"
    DOCKER_FILE=Dockerfile.ubuntu_for_android
    docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg PYTHON_VERSION=${PYTHON_VER} -f $DOCKER_FILE .
elif [ $BUILD_OS = "manylinux2010" ]; then
    if [ $BUILD_DEVICE = "gpu" ]; then
        IMAGE="manylinux2010-cuda10.1"
        DOCKER_FILE=Dockerfile.manylinux2010_gpu
    else
        IMAGE="manylinux2010"
        DOCKER_FILE=Dockerfile.manylinux2010
    fi
    docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg PYTHON_VERSION=${PYTHON_VER} -f $DOCKER_FILE .
else
    if [ $BUILD_DEVICE = "gpu" ]; then
        IMAGE="ubuntu16.04-$CUDA_VER"
        DOCKER_FILE=Dockerfile.ubuntu_gpu
        if [ $CUDA_VER = "cuda9.1-cudnn7.1" ]; then
        DOCKER_FILE=Dockerfile.ubuntu_gpu_cuda9
        fi
        docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg PYTHON_VERSION=${PYTHON_VER} -f $DOCKER_FILE .
    elif [ $BUILD_DEVICE = "tensorrt" ]; then
        IMAGE="ubuntu16.04-cuda10.0-cudnn7.4-tensorrt5.0"
        DOCKER_FILE=Dockerfile.ubuntu_tensorrt
        docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg PYTHON_VERSION=${PYTHON_VER} -f $DOCKER_FILE .
    elif [ $BUILD_DEVICE = "openvino" ]; then
        IMAGE="ubuntu16.04-openvino"
        DOCKER_FILE=Dockerfile.ubuntu_openvino
        docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg OS_VERSION=16.04 --build-arg PYTHON_VERSION=${PYTHON_VER} --build-arg OPENVINO_VERSION=${OPENVINO_VERSION} -f $DOCKER_FILE .
    else
        IMAGE="ubuntu16.04"
        if [ $BUILD_ARCH = "x86" ]; then
            IMAGE="$IMAGE.x86"
            docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg OS_VERSION=16.04 --build-arg PYTHON_VERSION=${PYTHON_VER} -f Dockerfile.ubuntu_x86 .
        else
            docker build -t "onnxruntime-$IMAGE" --build-arg BUILD_USER=onnxruntimedev --build-arg BUILD_UID=$(id -u) --build-arg OS_VERSION=16.04 --build-arg PYTHON_VERSION=${PYTHON_VER} -f Dockerfile.ubuntu .
        fi
    fi
fi

set +e
mkdir -p ~/.cache/onnxruntime
mkdir -p ~/.onnx

if [ -z "$NIGHTLY_BUILD" ]; then
    set NIGHTLY_BUILD=0
fi

if [ $BUILD_DEVICE = "cpu" ] || [ $BUILD_DEVICE = "ngraph" ] || [ $BUILD_DEVICE = "openvino" ] || [ $BUILD_DEVICE = "nnapi" ]; then
    RUNTIME=
else
    RUNTIME="--runtime=nvidia"
fi

DOCKER_RUN_PARAMETER="--name onnxruntime-$BUILD_DEVICE \
                      --volume $SOURCE_ROOT:/onnxruntime_src \
                      --volume $BUILD_DIR:/build \
                      --volume $HOME/.cache/onnxruntime:/home/onnxruntimedev/.cache/onnxruntime \
                      --volume $HOME/.onnx:/home/onnxruntimedev/.onnx"
if [ $BUILD_DEVICE = "openvino" ] && [[ $BUILD_EXTR_PAR == *"--use_openvino GPU_FP"* ]]; then
    DOCKER_RUN_PARAMETER="$DOCKER_RUN_PARAMETER --device /dev/dri:/dev/dri"
fi

docker rm -f "onnxruntime-$BUILD_DEVICE" || true
docker run $RUNTIME -h $HOSTNAME $DOCKER_RUN_PARAMETER \
    -e NIGHTLY_BUILD \
    "onnxruntime-$IMAGE" \
    /bin/bash /onnxruntime_src/tools/ci_build/github/linux/run_build.sh \
    -d $BUILD_DEVICE -x "$BUILD_EXTR_PAR" -o $BUILD_OS &
wait $!

EXIT_CODE=$?

set -e
exit $EXIT_CODE
