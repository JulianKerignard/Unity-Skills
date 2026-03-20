# Animation Avancee - Reference

Reference technique pour les systemes d'animation avances dans Unity.

## 1. Root Motion

**Quand activer** : locomotion realiste (mocap), combat avec deplacement integre (dash, lunge).
**Quand desactiver** : gameplay arcade, controles precis, objets simples.

### Setup

1. Verifier que les root curves existent dans le clip (model import)
2. Cocher "Apply Root Motion" sur l'Animator component
3. Le transform sera pilote par les curves root de l'animation

### Integration NavMeshAgent

```csharp
[RequireComponent(typeof(Animator))]
[RequireComponent(typeof(NavMeshAgent))]
public class NavMeshRootMotion : MonoBehaviour
{
    private NavMeshAgent agent;
    private Animator animator;
    private static readonly int SpeedHash = Animator.StringToHash("Speed");

    private void Awake()
    {
        agent = GetComponent<NavMeshAgent>();
        animator = GetComponent<Animator>();
        agent.updatePosition = false;
        agent.updateRotation = false;
    }

    private void Update()
    {
        float speed = agent.desiredVelocity.magnitude;
        animator.SetFloat(SpeedHash, speed, 0.1f, Time.deltaTime);

        if (agent.desiredVelocity.sqrMagnitude > 0.01f)
        {
            var lookRotation = Quaternion.LookRotation(agent.desiredVelocity);
            transform.rotation = Quaternion.Slerp(
                transform.rotation, lookRotation, 5f * Time.deltaTime);
        }
    }

    private void OnAnimatorMove()
    {
        agent.velocity = animator.deltaPosition / Time.deltaTime;
        transform.rotation = animator.rootRotation;
    }
}
```

### Root Motion partiel (Y uniquement)

```csharp
private void OnAnimatorMove()
{
    var pos = transform.position;
    pos.y += animator.deltaPosition.y;
    transform.position = pos;
    transform.rotation = animator.rootRotation;
}
```

## 2. IK -- Animation Rigging Package

Package : `com.unity.animation.rigging`. Setup : Rig Builder sur root, child "Rig" avec component Rig, constraints en children.

### Constraints

| Constraint | Usage | Exemple |
|-----------|-------|---------|
| Two Bone IK | Bras / jambes | Attraper objet, pieds terrain |
| Multi-Aim | Tete/torse suit cible | Regard ennemi |
| Multi-Position | Position suit cible | Main sur poignee |
| Multi-Parent | Re-parente dynamique | Arme change de main |
| Damped Transform | Follow avec inertie | Queue, cheveux |
| Chain IK | Chaine de bones | Tentacule |

### Look At avec falloff

```csharp
public class LookAtTarget : MonoBehaviour
{
    [SerializeField] private Rig lookRig;
    [SerializeField] private Transform lookTarget;
    [SerializeField] private float maxAngle = 70f;
    [SerializeField] private float weightSpeed = 5f;

    private void Update()
    {
        var dir = (lookTarget.position - transform.position).normalized;
        var angle = Vector3.Angle(transform.forward, dir);
        float target = angle < maxAngle ? 1f : 0f;
        lookRig.weight = Mathf.MoveTowards(
            lookRig.weight, target, weightSpeed * Time.deltaTime);
    }
}
```

### Foot IK sur terrain

```csharp
public class FootPlacement : MonoBehaviour
{
    [SerializeField] private Transform leftFootTarget, rightFootTarget;
    [SerializeField] private Transform leftFoot, rightFoot;
    [SerializeField] private float raycastDistance = 1.5f;
    [SerializeField] private LayerMask groundLayer;

    private void LateUpdate()
    {
        PlaceFoot(leftFoot, leftFootTarget);
        PlaceFoot(rightFoot, rightFootTarget);
    }

    private void PlaceFoot(Transform foot, Transform target)
    {
        var origin = foot.position + Vector3.up * 0.5f;
        if (Physics.Raycast(origin, Vector3.down, out var hit, raycastDistance, groundLayer))
        {
            target.position = hit.point;
            target.rotation = Quaternion.FromToRotation(Vector3.up, hit.normal)
                * transform.rotation;
        }
    }
}
```

## 3. Blend Trees avances

| Type | Parametres | Cas d'usage |
|------|-----------|-------------|
| 1D | 1 float | Vitesse : idle - walk - run |
| 2D Simple Directional | 2 floats | 4/8 directions discretes |
| 2D Freeform Directional | 2 floats | Mouvement libre joystick |
| 2D Freeform Cartesian | 2 floats | Axes independants (lean X+Y) |
| Direct | N floats | Poids direct par clip (facial) |

### 2D Freeform Directional layout

```
        (0, 1) Forward
(-1, 0) Left    (1, 0) Right        Intermediaires: (+-0.7, +-0.7)
        (0, 0) Idle
        (0, -1) Backward
```

### Direct Blend Tree (facial)

```csharp
private static readonly int FaceHappyHash = Animator.StringToHash("FaceHappy");
private static readonly int FaceSadHash = Animator.StringToHash("FaceSad");

public void SetEmotion(float happy, float sad)
{
    animator.SetFloat(FaceHappyHash, happy);
    animator.SetFloat(FaceSadHash, sad);
}
```

## 4. Timeline

**PlayableDirector** controle la timeline. **TimelineAsset** est reutilisable entre scenes.

### Tracks standard

| Track | Role |
|-------|------|
| Animation | Override l'Animator |
| Activation | Active/desactive GameObject |
| Audio | Joue AudioClips |
| Signal | Declenche events custom |
| Cinemachine | Controle cameras |
| Control | Sub-timeline ou ParticleSystem |

### Controle via code

```csharp
public class CutsceneController : MonoBehaviour
{
    [SerializeField] private PlayableDirector director;
    [SerializeField] private GameObject playerInput;

    public void PlayCutscene()
    {
        playerInput.SetActive(false);
        director.Play();
        director.stopped += OnCutsceneEnd;
    }

    private void OnCutsceneEnd(PlayableDirector d)
    {
        d.stopped -= OnCutsceneEnd;
        playerInput.SetActive(true);
    }

    public void SkipCutscene()
    {
        director.time = director.duration;
        director.Evaluate();
        director.Stop();
    }
}
```

### Custom PlayableBehaviour (dialogue track)

```csharp
public class DialoguePlayableBehaviour : PlayableBehaviour
{
    public string dialogueText;

    public override void OnBehaviourPlay(Playable playable, FrameData info)
        => DialogueUI.Instance?.ShowText(dialogueText);

    public override void OnBehaviourPause(Playable playable, FrameData info)
        => DialogueUI.Instance?.HideText();
}
```

## 5. Playables API

Pour mixer des animations dynamiquement a runtime, layering dynamique, animation procedurale.

```csharp
public class PlayableMixer : MonoBehaviour
{
    [SerializeField] private AnimationClip clipA, clipB;
    [Range(0f, 1f)] [SerializeField] private float blendFactor;
    private PlayableGraph graph;
    private AnimationMixerPlayable mixer;

    private void OnEnable()
    {
        graph = PlayableGraph.Create("CustomMixer");
        graph.SetTimeUpdateMode(DirectorUpdateMode.GameTime);
        mixer = AnimationMixerPlayable.Create(graph, 2);

        var a = AnimationClipPlayable.Create(graph, clipA);
        var b = AnimationClipPlayable.Create(graph, clipB);
        graph.Connect(a, 0, mixer, 0);
        graph.Connect(b, 0, mixer, 1);

        var output = AnimationPlayableOutput.Create(graph, "out", GetComponent<Animator>());
        output.SetSourcePlayable(mixer);
        graph.Play();
    }

    private void Update()
    {
        mixer.SetInputWeight(0, 1f - blendFactor);
        mixer.SetInputWeight(1, blendFactor);
    }

    private void OnDisable()
    {
        if (graph.IsValid()) graph.Destroy();
    }
}
```

### Multi-layer via Playables

```csharp
var layerMixer = AnimationLayerMixerPlayable.Create(graph, 2);
layerMixer.SetLayerMaskFromAvatarMask(1, upperBodyMask);
layerMixer.SetInputWeight(0, 1f);          // base locomotion
layerMixer.SetInputWeight(1, attackWeight); // upper body override
```

## 6. State Machine patterns avances

### Sub-State Machines

```
Root
+-- Locomotion: Idle, Walk, Run, Sprint
+-- Combat: Attack1, Attack2, Block, Dodge
+-- Interaction: Pickup, Talk, Use
```

### Any State transitions

- Hit Reaction : Any State --> HitReaction (trigger "Hit")
- Death : Any State --> Death (trigger "Die")
- Toujours mettre "Can Transition To Self = false"

### Override Controller

```csharp
public class CharacterSkin : MonoBehaviour
{
    [SerializeField] private RuntimeAnimatorController baseController;
    [SerializeField] private AnimationClip[] overrideClips;
    [SerializeField] private string[] originalClipNames;

    private void Start()
    {
        var oc = new AnimatorOverrideController(baseController);
        var overrides = new List<KeyValuePair<AnimationClip, AnimationClip>>();
        var originals = oc.animationClips;

        for (int i = 0; i < originalClipNames.Length; i++)
        {
            var orig = System.Array.Find(originals, c => c.name == originalClipNames[i]);
            if (orig != null)
                overrides.Add(new(orig, overrideClips[i]));
        }
        oc.ApplyOverrides(overrides);
        GetComponent<Animator>().runtimeAnimatorController = oc;
    }
}
```

### StateMachineBehaviour avance

```csharp
public class RandomIdleState : StateMachineBehaviour
{
    [SerializeField] private float minIdleTime = 3f, maxIdleTime = 8f;
    private float idleTimer;
    private static readonly int RandomIdleHash = Animator.StringToHash("RandomIdle");

    public override void OnStateEnter(Animator animator, AnimatorStateInfo si, int layer)
        => idleTimer = Random.Range(minIdleTime, maxIdleTime);

    public override void OnStateUpdate(Animator animator, AnimatorStateInfo si, int layer)
    {
        idleTimer -= Time.deltaTime;
        if (idleTimer <= 0f) animator.SetTrigger(RandomIdleHash);
    }
}
```

## 7. Performance tips

| Conseil | Raison |
|---------|--------|
| `Animator.StringToHash` partout | Evite allocation string et lookup par nom |
| Reduire layers actifs | Chaque layer evalue toute la state machine |
| Desactiver Animator hors camera | `animator.enabled = false` ou Culling Mode |
| Eviter `GetCurrentAnimatorStateInfo` dans Update | Couteux, preferer StateMachineBehaviour |
| Compresser clips a l'import | "Anim. Compression" = "Optimal" |
| Limiter Animation Events | Overhead par event, regrouper si possible |
| Pooler Override Controllers | Creer une fois, reutiliser entre spawns |
