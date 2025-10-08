extends Control

## Some margin to keep the marker away from the screen's corners.
const MARGIN = 8

@export var use_spatial_prompt: bool = false
@export var use_centered_prompt: bool = true  # Nova opção: centralizar no centro visual (AABB)

@onready var camera := get_viewport().get_camera_3d()
@onready var parent := get_parent()

func _process(_delta: float) -> void:
	if !use_spatial_prompt:
		visible = false
		return
	
	var interactable = parent.player.player_interaction_component.interactable
	if interactable == null:
		visible = false
		return
	else:
		visible = true
	
	# Garante que temos uma câmera válida e atual
	if not camera or not camera.current:
		camera = get_viewport().get_camera_3d()
		if not camera:
			visible = false
			return

	# Determina a posição alvo: origem ou centro da AABB
	var target_position: Vector3
	if use_centered_prompt:
		target_position = _get_interactable_center(interactable)
	else:
		target_position = interactable.global_transform.origin

	var camera_transform := camera.global_transform
	var camera_position := camera_transform.origin

	# Verifica se o alvo está atrás da câmera
	var is_behind := camera_transform.basis.z.dot(target_position - camera_position) > 0

	# Projeta a posição 3D para 2D na tela
	var unprojected_position := camera.unproject_position(target_position)
	
	# Obtém o tamanho base do viewport (considerando escala de conteúdo)
	var viewport_base_size: Vector2i = (
		get_viewport().content_scale_size if get_viewport().content_scale_size > Vector2i(0, 0)
		else get_viewport().size
	)

	# Ajuste no eixo X: se estiver atrás, empurra para os lados
	if is_behind:
		if unprojected_position.x < viewport_base_size.x / 2:
			unprojected_position.x = viewport_base_size.x - MARGIN
		else:
			unprojected_position.x = MARGIN

	# Ajuste no eixo Y: usa diferença angular para objetos atrás ou nas bordas
	if is_behind or unprojected_position.x < MARGIN or \
			unprojected_position.x > viewport_base_size.x - MARGIN:
		var look := camera_transform.looking_at(target_position, Vector3.UP)
		var diff := angle_difference(look.basis.get_euler().x, camera_transform.basis.get_euler().x)
		unprojected_position.y = viewport_base_size.y * (0.5 + (diff / deg_to_rad(camera.fov)))

	# Aplica margens e define a posição final do Control
	position = Vector2(
		clamp(unprojected_position.x, MARGIN, viewport_base_size.x - MARGIN),
		clamp(unprojected_position.y, MARGIN, viewport_base_size.y - MARGIN)
	)

	# Reseta rotação e calcula overflow para setas diagonais
	rotation = 0
	var overflow := 0

	if position.x <= MARGIN:
		# Esquerda
		overflow = int(-TAU / 8.0)
		rotation = TAU / 4.0
	elif position.x >= viewport_base_size.x - MARGIN:
		# Direita
		overflow = int(TAU / 8.0)
		rotation = TAU * 3.0 / 4.0

	if position.y <= MARGIN:
		# Cima
		rotation = TAU / 2.0 + overflow
	elif position.y >= viewport_base_size.y - MARGIN:
		# Baixo
		rotation = -overflow

# Retorna o centro visual (AABB global) do objeto interagível
func _get_interactable_center(node: Node) -> Vector3:
	var aabb: AABB = _get_node_aabb(node)
	if aabb != AABB():
		return aabb.get_center()
	else:
		# Fallback: usa a origem se não houver geometria visual
		return node.global_transform.origin

# Obtém a AABB global combinada de um nó e seus filhos visuais
func _get_node_aabb(node: Node) -> AABB:
	# Se for uma instância visual com geometria, pega sua AABB
	if node is VisualInstance3D:
		var local_aabb: AABB = node.get_aabb()
		if local_aabb.size != Vector3.ZERO:
			# Transforma a AABB para o espaço global
			var transform: Transform3D = node.global_transform
			var global_aabb: AABB = transform * local_aabb
			return global_aabb

	# Se for um nó 3D (container), busca recursivamente nos filhos
	if node is Node3D:
		var combined_aabb := AABB()
		for child in node.get_children():
			var child_aabb = _get_node_aabb(child)
			if child_aabb != AABB():
				if combined_aabb == AABB():
					combined_aabb = child_aabb
				else:
					combined_aabb = combined_aabb.merge(child_aabb)
		return combined_aabb

	# Nós não 3D ou sem geometria retornam AABB vazia
	return AABB()
