#include "physics.hpp"

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyFilter.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceTable.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterTable.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterTable.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include <stdexcept>
#include <string>

namespace {

constexpr JPH::ObjectLayer kLayer = 0;
constexpr float kGravity = 9.8f;
constexpr float kRadius = 0.3f;
constexpr float kHalfCylinder = 0.15f;
constexpr float kStepUp = 0.2f;
constexpr float kMaxSlopeDegrees = 45.0f;
constexpr float kWallHeight = 3.0f;
constexpr float kSlab = 0.5f;

JPH::Vec3 vec(glm::vec3 v) { return {v.x, v.y, v.z}; }

JPH::RefConst<JPH::Shape> create(const JPH::ShapeSettings& settings) {
    JPH::ShapeSettings::ShapeResult result = settings.Create();
    if (result.HasError()) throw std::runtime_error(std::string("Jolt shape: ") + result.GetError().c_str());
    return result.Get();
}

/** LOD 0 triangles in model space (node transforms and the unit-sphere root applied). */
JPH::TriangleList scene_triangles(const SceneData& scene) {
    JPH::TriangleList triangles;
    for (const DrawData& d : scene.lods[0]) {
        for (uint32_t i = d.first_index; i + 2 < d.first_index + d.index_count; i += 3) {
            JPH::Float3 corner[3];
            for (uint32_t k = 0; k < 3; k++) {
                const float* p = scene.vertices[scene.indices[i + k]].position;
                const glm::vec4 w = d.transform * glm::vec4(p[0], p[1], p[2], 1.0f);
                corner[k] = {w.x, w.y, w.z};
            }
            triangles.emplace_back(corner[0], corner[1], corner[2]);
        }
    }
    return triangles;
}

/** Jolt's process-wide allocator, factory and type registry for the lifetime of the world. */
struct JoltRuntime {
    JoltRuntime() {
        JPH::RegisterDefaultAllocator();
        JPH::Factory::sInstance = new JPH::Factory();
        JPH::RegisterTypes();
    }
    ~JoltRuntime() {
        JPH::UnregisterTypes();
        delete JPH::Factory::sInstance;
        JPH::Factory::sInstance = nullptr;
    }
    JoltRuntime(const JoltRuntime&) = delete;
    JoltRuntime& operator=(const JoltRuntime&) = delete;
};

/** One object layer and one broad-phase layer that collide with themselves. */
struct Layers {
    JPH::ObjectLayerPairFilterTable pairs{1};
    JPH::BroadPhaseLayerInterfaceTable broad_phase{1, 1};

    Layers() {
        pairs.EnableCollision(kLayer, kLayer);
        broad_phase.MapObjectToBroadPhaseLayer(kLayer, JPH::BroadPhaseLayer(0));
    }
};

}  // namespace

struct Physics::World {
    JoltRuntime runtime;
    Layers layers;
    JPH::ObjectVsBroadPhaseLayerFilterTable object_vs_broad_phase{layers.broad_phase, 1, layers.pairs, 1};
    JPH::TempAllocatorImpl temp{1 << 20};
    JPH::PhysicsSystem system;
    JPH::BodyID turntable;
    JPH::RVec3 turntable_at;
    JPH::IgnoreMultipleBodiesFilter walls;
    JPH::Ref<JPH::CharacterVirtual> character;

    JPH::BodyID add(const JPH::BodyCreationSettings& settings) {
        return system.GetBodyInterface().CreateAndAddBody(settings, JPH::EActivation::DontActivate);
    }
};

Physics::Physics(const SceneData& scene, float arena_half, glm::vec3 feet) : world_(std::make_unique<World>()) {
    World& w = *world_;
    w.system.Init(16, 0, 16, 16, w.layers.broad_phase, w.object_vs_broad_phase, w.layers.pairs);

    const float h = arena_half + kSlab;
    w.add({create(JPH::BoxShapeSettings({h, kSlab, h})), {0, -kSlab, 0}, JPH::Quat::sIdentity(), JPH::EMotionType::Static, kLayer});
    const JPH::RefConst<JPH::Shape> wall = create(JPH::BoxShapeSettings({kSlab, kWallHeight, h}));
    for (int side = 0; side < 4; side++) {
        const float sign = side & 1 ? -1.0f : 1.0f;
        const JPH::Quat turn = JPH::Quat::sRotation(JPH::Vec3::sAxisY(), side < 2 ? 0.0f : 0.5f * JPH::JPH_PI);
        w.walls.IgnoreBody(w.add({wall, turn * JPH::Vec3(sign * h, kWallHeight, 0), turn, JPH::EMotionType::Static, kLayer}));
    }

    w.turntable_at = JPH::RVec3(0, -lowest_y(scene.lods[0]), 0);
    JPH::BodyCreationSettings turntable(create(JPH::MeshShapeSettings(scene_triangles(scene))), w.turntable_at,
                                        JPH::Quat::sIdentity(), JPH::EMotionType::Kinematic, kLayer);
    turntable.mOverrideMassProperties = JPH::EOverrideMassProperties::MassAndInertiaProvided;
    turntable.mMassPropertiesOverride.mMass = 1.0f;
    w.turntable = w.system.GetBodyInterface().CreateAndAddBody(turntable, JPH::EActivation::DontActivate);
    w.system.OptimizeBroadPhase();

    JPH::CharacterVirtualSettings settings;
    settings.mShape = create(JPH::RotatedTranslatedShapeSettings(JPH::Vec3(0, kHalfCylinder + kRadius, 0), JPH::Quat::sIdentity(),
                                                                 new JPH::CapsuleShapeSettings(kHalfCylinder, kRadius)));
    settings.mMaxSlopeAngle = JPH::DegreesToRadians(kMaxSlopeDegrees);
    settings.mSupportingVolume = JPH::Plane(JPH::Vec3::sAxisY(), -kRadius);
    w.character = new JPH::CharacterVirtual(&settings, JPH::RVec3(vec(feet)), JPH::Quat::sIdentity(), 0, &w.system);
}

Physics::~Physics() = default;

void Physics::step(glm::vec3 walk_velocity, float jump_speed, float turntable_angle, float dt) {
    World& w = *world_;
    w.system.GetBodyInterface().SetPositionAndRotation(
        w.turntable, w.turntable_at, JPH::Quat::sRotation(JPH::Vec3::sAxisY(), turntable_angle), JPH::EActivation::DontActivate);

    const JPH::Vec3 gravity(0, -kGravity, 0);
    float vertical = w.character->GetLinearVelocity().GetY();
    if (grounded()) vertical = jump_speed;
    vertical += gravity.GetY() * dt;
    w.character->SetLinearVelocity(JPH::Vec3(walk_velocity.x, vertical, walk_velocity.z));

    JPH::CharacterVirtual::ExtendedUpdateSettings update;
    update.mWalkStairsStepUp = JPH::Vec3(0, kStepUp, 0);
    w.character->ExtendedUpdate(dt, gravity, update, w.system.GetDefaultBroadPhaseLayerFilter(kLayer),
                                w.system.GetDefaultLayerFilter(kLayer), {}, {}, w.temp);
}

glm::vec3 Physics::feet() const {
    const JPH::RVec3 p = world_->character->GetPosition();
    return {p.GetX(), p.GetY(), p.GetZ()};
}

float Physics::ray(glm::vec3 from, glm::vec3 to) const {
    JPH::RayCastResult hit;
    const JPH::NarrowPhaseQuery& query = world_->system.GetNarrowPhaseQuery();
    return query.CastRay(JPH::RRayCast(JPH::RVec3(vec(from)), vec(to - from)), hit, {}, {}, world_->walls) ? hit.mFraction : 1.0f;
}

bool Physics::grounded() const { return world_->character->GetGroundState() == JPH::CharacterVirtual::EGroundState::OnGround; }
