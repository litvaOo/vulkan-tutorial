run: build-shaders
	mkdir -p target/ && odin run . -out:target/main -debug -o:aggressive 

build-shaders:
	glslc shaders/shader.frag -o frag.spv
	glslc shaders/shader.vert -o vert.spv
