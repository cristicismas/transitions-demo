package transitions_simple

import hm "core:container/handle_map"
import "core:math/ease"
import "core:math/linalg"
import rl "vendor:raylib"

vec2 :: rl.Vector2

Transition :: struct {
	// The initial value that the transition will start from. You can pass the current value of the variable, or another value entirely.
	initial:       f32,
	// The final value that our variable will reach at the end of the transition.
	final:         f32,
	// The duration of the transition, passed in seconds
	time:          f32,
	// Here we can use whatever we define in the struct below. We later match on these using Odin's math/ease functions as the interpolator for non-linear easings.
	easing:        Transition_Easing,
	// This is needed for the Handle_Map to work properly. You should not pass this when creating the Transition. It is however a member of this struct to avoid creating another one just for the sake of avoiding a few extra members.
	handle:        Transition_Id,
	// These are used for the internal logic only, which is why they are underscored. They should not be passed when creating the transition.
	_data_pointer: ^f32,
	_time_passed:  f32,
}

Transition_Easing :: enum {
	Linear,
	Sine_In,
	Sine_Out,
}

// This is that maximum amount of transitions we will have in our application. That means we are allocating up-front the cost of them maxium amount of transitions.
TRANSITIONS_MAP_CAP :: 2048

// This defines the Transitions_Handle_Map type
Transition_Id :: distinct hm.Handle32
Transitions_Handle_Map :: hm.Static_Handle_Map(TRANSITIONS_MAP_CAP, Transition, Transition_Id)

// The transitions handle_map. Make sure you define this above the main procedure.
transitions: Transitions_Handle_Map

main :: proc() {
	rl.InitWindow(1280, 720, "Transitions Demo")

	rl.SetTargetFPS(144)

	pos := vec2{50, 50}
	size := vec2{50, 50}

	start_transition(&pos.x, Transition{initial = 50, final = 550, time = 2, easing = .Sine_In})
	start_transition(&size.y, Transition{initial = 50, final = 100, time = 2, easing = .Sine_Out})

	for !rl.WindowShouldClose() {
		update_transitions(&transitions)

		rl.BeginDrawing()

		rl.ClearBackground(rl.DARKBLUE)
		rl.DrawRectangleV(pos, size, rl.WHITE)

		rl.EndDrawing()
	}

	rl.CloseWindow()
}

update_transitions :: proc(transitions: ^Transitions_Handle_Map) {
	it := hm.iterator_make(transitions)

	// Here we use the raylib's function to get the time since the last frame.
	// If you use another graphics library, feel free to use that library's function
	// Just keep in mind that in raylib this time is in seconds, so you may need to adjust appropriately.
	delta := rl.GetFrameTime()

	for transition, handle in hm.iterate(&it) {
		transition._time_passed += delta

		update_transition_value(transition)

		// If any transition has passed its expiration date, then remove it from the handle map. Its slot in the handle map will be reused later if another transition is added.
		if transition._time_passed >= transition.time {
			hm.remove(transitions, handle)
		}
	}
}

update_transition_value :: proc(transition: ^Transition) {
	progress: f32

	// In case the time passed to the transition is 0, we just set the progress to 1 to avoid division by 0 in the other branch.
	if transition.time == 0 {
		progress = 1
	} else {
		progress = min(transition._time_passed, transition.time) / transition.time
	}

	// If the easing type is linear, the interpolator is simply our computed progress based on time passed.
	interpolator := progress

	// If the easing type is not linear, we will update our interpolator using the easing functions in the 'ease' package
	switch transition.easing {
	case .Linear:
	case .Sine_In:
		interpolator = ease.sine_in(interpolator)
	case .Sine_Out:
		interpolator = ease.sine_out(interpolator)
	// Add more easing types from the 'ease' package if you want
	}

	initial := transition.initial
	final := transition.final

	// update the value based on our interpolator
	transition._data_pointer^ = linalg.lerp(initial, final, interpolator)
}

start_transition :: proc(
	data_pointer: ^f32,
	transition: Transition,
	// loc is just used to get better error messages out.
	// It gives us the source-code location of where this function was called.
	loc := #caller_location,
) -> Transition_Id {
	if transition.time < 0 {
		panic("Transition time cannot be < 0.", loc = loc)
	}

	// make a local copy of transition so we can change its fields
	transition := transition

	// Set the struct's internal member to the first parameter.
	//
	// NOTE: We could have also just passed this inside the struct, which would have removed a parameter from this procedure.
	// However, I decided I liked the api better if the first paramater is the pointer to the data, because it means it's
	// impossible to forget to pass it. It also makes it very clear which variable we are trying to transition.
	transition._data_pointer = data_pointer

	// Set the value instantly to the initial_value passed to the struct
	data_pointer^ = transition.initial

	// Just add our transition to the handle map. The update_transitions procedure will take care of the rest.
	handle, add_ok := hm.add(&transitions, transition)

	if !add_ok {
		panic("Failed to a transition to the handle map.", loc = loc)
	}

	return handle
}
