package dev.wizig.wizigapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.wizig.WizigGeneratedApi
import dev.wizig.wizigapp.ui.theme.WizigAppTheme

class MainActivity : ComponentActivity() {
    companion object {
        init {
            // The Zig FFI library is built without a bionic dependency, so its
            // thread-local symbols (__tls_get_addr) only resolve if the linker
            // sees libc while loading it. libwizigjni links both the FFI library
            // and libc, so loading it first loads the FFI library in a linker
            // scope that has libc in it. Loading the FFI library on its own
            // (which is what the generated bridge does) fails on x86_64 and
            // crashes on the first TLS access on arm64.
            // runCatching keeps a missing library on the error-card path instead
            // of failing class initialisation and killing the process.
            runCatching { System.loadLibrary("wizigjni") }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WizigAppTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    CalculatorScreen(modifier = Modifier.padding(innerPadding))
                }
            }
        }
    }
}

/** Everything the host can ask the shared Zig library to compute. */
private class Calculators(private val api: WizigGeneratedApi) {
    fun randomInt(min: String, max: String) = api.randomInt("$min $max")
    fun rollDice(spec: String) = api.rollDice(spec)
    fun coinFlip() = api.coinFlip()
    fun password(length: String) = api.password(length)
    fun bmi(kg: String, cm: String) = api.bmi("$kg $cm")
    fun tipSplit(bill: String, percent: String, people: String) = api.tipSplit("$bill $percent $people")
    fun compound(principal: String, rate: String, years: String) = api.compound("$principal $rate $years")
}

@Composable
private fun CalculatorScreen(modifier: Modifier = Modifier) {
    val setup = remember { runCatching { Calculators(WizigGeneratedApi()) } }
    val calculations = setup.getOrNull()

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("🐣 WizigApp", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Random little calculators. The math runs in shared Zig code, the UI is Jetpack Compose.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (calculations == null) {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            ) {
                Text(
                    "Native Wizig runtime unavailable: " +
                        (setup.exceptionOrNull()?.message ?: "unknown error"),
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        } else {
            RandomNumberCard(calculations)
            DiceCard(calculations)
            CoinFlipCard(calculations)
            PasswordCard(calculations)
            TipSplitCard(calculations)
            BmiCard(calculations)
            CompoundCard(calculations)
        }
    }
}

@Composable
private fun ToolCard(
    title: String,
    description: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            content()
        }
    }
}

@Composable
private fun NumberField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = modifier,
    )
}

@Composable
private fun ResultText(result: String) {
    Text(
        text = result,
        fontFamily = FontFamily.Monospace,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
    )
}

/** Runs a calculator call lazily, turning bridge exceptions into readable text. */
private inline fun attempt(call: () -> String): String =
    runCatching { call() }.getOrElse { "error: ${it.message ?: it::class.simpleName}" }

@Composable
private fun RandomNumberCard(calculations: Calculators) {
    var min by rememberSaveable { mutableStateOf("1") }
    var max by rememberSaveable { mutableStateOf("100") }
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("Random number", "Uniform integer between two bounds (Zig entropy).") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NumberField("Min", min, { min = it }, Modifier.weight(1f))
            NumberField("Max", max, { max = it }, Modifier.weight(1f))
        }
        Button(onClick = { result = attempt { calculations.randomInt(min, max) } }) {
            Text("Pick a number")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Composable
private fun DiceCard(calculations: Calculators) {
    var spec by rememberSaveable { mutableStateOf("2d6") }
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("Dice", "Rolls like 2d6 or 4d20 and shows every face.") {
        OutlinedTextField(
            value = spec,
            onValueChange = { spec = it },
            label = { Text("Dice (count d sides)") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = { result = attempt { calculations.rollDice(spec) } }) {
            Text("Roll")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Composable
private fun CoinFlipCard(calculations: Calculators) {
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("Coin flip", "Heads or tails, fifty-fifty.") {
        Button(onClick = { result = attempt { calculations.coinFlip() } }) {
            Text("Flip the coin")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Composable
private fun PasswordCard(calculations: Calculators) {
    var length by rememberSaveable { mutableStateOf("16") }
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("Password", "One character from each class, no lookalikes (l, I, 0, O).") {
        NumberField("Length", length, { length = it }, Modifier.fillMaxWidth())
        Button(onClick = { result = attempt { calculations.password(length) } }) {
            Text("Generate")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Composable
private fun TipSplitCard(calculations: Calculators) {
    var bill by rememberSaveable { mutableStateOf("100") }
    var percent by rememberSaveable { mutableStateOf("15") }
    var people by rememberSaveable { mutableStateOf("2") }
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("Tip split", "Tip, total, and what everyone puts in.") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NumberField("Bill", bill, { bill = it }, Modifier.weight(1f))
            NumberField("Tip %", percent, { percent = it }, Modifier.weight(1f))
        }
        NumberField("People", people, { people = it }, Modifier.fillMaxWidth())
        Button(onClick = { result = attempt { calculations.tipSplit(bill, percent, people) } }) {
            Text("Split")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Composable
private fun BmiCard(calculations: Calculators) {
    var kg by rememberSaveable { mutableStateOf("70") }
    var cm by rememberSaveable { mutableStateOf("175") }
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("BMI", "Body mass index with the usual bands.") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NumberField("Weight (kg)", kg, { kg = it }, Modifier.weight(1f))
            NumberField("Height (cm)", cm, { cm = it }, Modifier.weight(1f))
        }
        Button(onClick = { result = attempt { calculations.bmi(kg, cm) } }) {
            Text("Calculate")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Composable
private fun CompoundCard(calculations: Calculators) {
    var principal by rememberSaveable { mutableStateOf("1000") }
    var rate by rememberSaveable { mutableStateOf("7") }
    var years by rememberSaveable { mutableStateOf("10") }
    var result by rememberSaveable { mutableStateOf("") }

    ToolCard("Compound interest", "What a lump sum turns into, yearly compounding.") {
        NumberField("Starting amount", principal, { principal = it }, Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NumberField("Rate % / yr", rate, { rate = it }, Modifier.weight(1f))
            NumberField("Years", years, { years = it }, Modifier.weight(1f))
        }
        Button(onClick = { result = attempt { calculations.compound(principal, rate, years) } }) {
            Text("Grow it")
        }
        if (result.isNotEmpty()) ResultText(result)
    }
}

@Preview(showBackground = true)
@Composable
private fun CalculatorScreenPreview() {
    WizigAppTheme(dynamicColor = false) {
        CalculatorScreen()
    }
}
